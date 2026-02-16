# Hydration branch

This branch is used for hydrated manifests located in `hydrated-manifests` folder which are used by ArgoCD.
Besides this folder this branch should be empty. The hydration workflow creates automated PRs from the main branch using a
`values-<env>.yaml` file corresponding to this branch.