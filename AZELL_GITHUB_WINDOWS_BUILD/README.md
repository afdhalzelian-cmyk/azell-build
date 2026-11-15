# Azell Windows x64 build repository

This folder is the initial content of a private GitHub repository for Azell. It contains a pinned Cherry Studio integration patch, the Windows build script, and a manual GitHub Actions workflow. It does not contain databases, backups, credentials, or personal files.

Commit this folder's contents to the default branch, including the hidden `.github` directory. The workflow's repository path must be `.github/workflows/build-windows.yml`. Start **Build Azell Windows x64** from the repository's **Actions** tab. GitHub-hosted runner usage is subject to your account's included minutes and billing settings.

The workflow fetches the public Cherry Studio source by commit, checks the Visual Studio C++ and ATL prerequisites, applies the patch, builds the installer and portable executable, verifies their PE headers, and uploads them with SHA-256 checksums. The build artifact is intended for release verification. The workflow has not been run on a Windows runner yet. The release ZIP, Windows launch test and live Ollama test are separate pending steps.
