# Falco on WSL 2 with a custom kernel

This page is based on the [post on the official falco blog](https://falco.org/blog/falco-wsl2-custom-kernel/) but updated with the current Linux kernel `6.5.7` and based on the current WSL kernel config `6.1.y`.

## Prerequisites

WSL is installed on your system which can be done with:

```PowerShell
wsl --install --distribution ubuntu
```

**Optional**: Update WSL to use the preview version:

```PowerShell
wsl --update --pre-release
```

Update the Ubuntu distro to use the latest `23.10` release. Launch the WSL terminal (`wsl -d ubuntu`) and check the current used version:

```bash
lsb_release -a
```

Change the `Prompt` setting in `/etc/update-manager/release-upgrades` to allow upgrades to non-LTS releases:

```bash
sudo vim /etc/update-manager/release-upgrades
# in the file change the Prompt setting
Prompt=normal
# save the setting (:wq)
```

To update to `23.10` repeat these steps until your version is `23.10`:

```bash
sudo apt update && sudo apt -y full-upgrade && sudo apt -y autoremove
exit # leave WSL shell into PowerShell shell
wsl --terminate ubuntu
wsl # login again into WSL, if this distro is not the default one, use wsl -d ubuntu
sudo do-release-upgrade  # use this if you are not yet at 23.04.0x LTS release
sudo do-release-upgrade -d # use this to allow upgrade to 23.10 as this version is not yet officially released at the time of writing
```

If you encounter the message `Failed to connect to https://changelogs.ubuntu.com/meta-release-development. Check your Internet connection or proxy settings` after the first upgrade, delete the automatically generated `/etc/hosts/resolv.conf` file and replace the content:

```bash
sudo rm /etc/.resolv.conf.swp
sudo rm /etc/resolv.conf
sudo vi /etc/resolv.conf
# place this content
nameserver 192.168.155.1
nameserver 10.195.2.12
nameserver 1.1.1.1
nameserver 1.0.0.1
```

After the final update to `23.10` leave the wsl shell and terminate the `ubuntu` distro:

```bash
exit
wsl --terminate ubuntu
wsl -d ubuntu # login again into the ubuntu distro
```

## A (custom) Kernel for WSL2

Start the WSL terminal, if not done yet, and execute these commands:

```bash
cd # change to home directory

# Source: https://raw.githubusercontent.com/microsoft/WSL2-Linux-Kernel/linux-msft-wsl-6.1.y/README.md
sudo apt install -y build-essential flex bison dwarves libssl-dev libelf-dev bc

# Get the latest stable Linux Kernel, but only the latest version of each file and only the specific branch we want
# git needs to be installed
git clone --depth 1 --branch linux-rolling-stable https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git

# Ensure the "stable" branch is the active one
cd linux
git checkout linux-rolling-stable

# Get the WSL optimized kernel config
wget https://raw.githubusercontent.com/microsoft/WSL2-Linux-Kernel/linux-msft-wsl-6.1.y/arch/x86/configs/config-wsl -O .config

# Change the LOCALVERSION value
sed -i 's/microsoft-standard-WSL2/generic/' ./.config

# Before we start the compilation, let's "update" the config file to include the newest Kernel options
make prepare

# Choose the default value for all options by pressing [ENTER] 

# make sure that CONFIG_DEBUG_INFO_BTF is set to y => should output true
cat .config | grep -q "CONFIG_DEBUG_INFO_BTF=y" && echo "true" || echo "false" 

# Now that everything is ready, let's compile the kernel
make -j $(nproc)

# Once the compilation is done, we can install the "optional" modules
sudo make modules_install

# Copy the kernel into a directory in the Windows filesystem 
# I recommend creating a wslkernel directory
mkdir /mnt/c/wslkernel
cp arch/x86/boot/bzImage /mnt/c/wslkernel/kernelfalco

# Last step, the kernel needs to be referenced in the file .wslconfig 
# I'm using vi but feel free to use your preferred text editor
vi /mnt/c/Users/<your username>/.wslconfig

## The content of the file should look like this
## Source: https://docs.microsoft.com/en-us/windows/wsl/wsl-config#wsl-2-settings
[wsl2]
kernel = c:\\wslkernel\\kernelfalco
swap = 0
localhostForwarding = true

exit # exits WSL shell into PowerShell
wsl --shutdown
wsl # launch WSL again
uname -a # should output the latest stable Linux Kernel
```

Now we can check if the kernel fulfills these [requirements](https://falco.org/docs/event-sources/kernel/#requirements) by using `bpftool`:

1. BPF ring buffer support
2. A kernel that exposes BTF

Follow the instructions described [here](https://github.com/libbpf/bpftool/blob/main/README.md) in the WSL shell to install `bpftool`:

```bash
cd
git clone --recurse-submodules https://github.com/libbpf/bpftool.git
cd bpftool/src
make install
```

Now check the requirements with a WSL shell:

```bash
sudo bpftool feature probe kernel | grep -q "map_type ringbuf is available" && echo "true" || echo "false" 
sudo bpftool feature probe kernel | grep -q "program_type tracing is available" && echo "true" || echo "false" 
```

If any of the requirements are not met you have to either use a kernel which supports these features or change the kernel config if the default config does not enable those features. 
## SystemD for WSL

SystemD can now be enabled directly in WSL via the `wsl.conf`, details see [here](https://learn.microsoft.com/en-us/windows/wsl/systemd#how-to-enable-systemd). 

Launch the WSL shell:

```bash
vi /etc/wsl.conf

## Paste this and save the file
[boot]
systemd=true

exit
wsl --shutdown
wsl

# verify that systemd is running
ps -aux | grep "systemd"
```

## Install falco with custom kernel

The installation is similar to the "normal" installation of falco but we will download the linux headers from the [Ubuntu kernel website](https://kernel.ubuntu.com/mainline/v6.5.7/). Launch the WSL terminal:

```bash
# Move to your WSL2 home directory
cd

# Run the step 1 of the Falco documentation: add the repo
curl -s https://falco.org/repo/falcosecurity-packages.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/falco.gpg
echo "deb https://download.falco.org/packages/deb stable main" | sudo tee -a /etc/apt/sources.list.d/falcosecurity.list
sudo apt update

# install this package which is required for linux-image-unsigned
sudo apt install -y linux-base 

# As stated above, for the step 2, let's download the Kernel headers packages
wget https://kernel.ubuntu.com/mainline/v6.5.7/amd64/linux-headers-6.5.7-060507-generic_6.5.7-060507.202310102154_amd64.deb
wget https://kernel.ubuntu.com/mainline/v6.5.7/amd64/linux-headers-6.5.7-060507_6.5.7-060507.202310102154_all.deb
wget https://kernel.ubuntu.com/mainline/v6.5.7/amd64/linux-modules-6.5.7-060507-generic_6.5.7-060507.202310102154_amd64.deb
wget https://kernel.ubuntu.com/mainline/v6.5.7/amd64/linux-image-unsigned-6.5.7-060507-generic_6.5.7-060507.202310102154_amd64.deb

# Install the packages in this exact order, as the headers "generic" is depending on the headers "all" and "image" is depending on the "modules" package
sudo dpkg -i linux-headers-6.5.7-060507-generic_6.5.7-060507.202310102154_amd64.deb
sudo dpkg -i linux-headers-6.5.7-060507_6.5.7-060507.202310102154_all.deb
sudo dpkg -i linux-modules-6.5.7-060507-generic_6.5.7-060507.202310102154_amd64.deb
sudo dpkg -i linux-image-unsigned-6.5.7-060507-generic_6.5.7-060507.202310102154_amd64.deb

# To build the BPF probe locally you need also clang toolchain
sudo apt install -y clang llvm

# Install Falco from the repository
sudo apt install -y falco 
```

After the installation we need to compile the `bpf` probe ourselves if we want to use the `modern-bpf` driver. There is no prebuilt driver for the `6.5.7-generic` kernel yet in this [repo](https://download.falco.org/?prefix=driver/), so the `falco-driver-loader` will compile it using the previously installed linux headers:

```bash
# Install the kernel module
sudo falco-driver-loader module
# Install the eBPF probe
sudo falco-driver-loader bpf

# Run falco with modern-bpf driver
sudo falco --modern-bpf
```