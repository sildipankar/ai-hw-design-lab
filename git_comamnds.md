# Git Commands Cheat Sheet

This repo lives here on your computer:

```powershell
D:\git_check
```

This repo publishes to GitHub here:

```text
https://github.com/sildipankar/ai-hw-design-lab
```

## 1. Every Time Before You Start

Open PowerShell and go to the repo folder:

```powershell
cd D:\git_check
git status
```

If it says something like this, you are clean:

```text
nothing to commit, working tree clean
```

## 2. Upload a Changed File

Example: `D:\design_plans\KID_GUIDE.md` changed, and you want to upload the new version as `kids_guide.md` in GitHub.

Run:

```powershell
cd D:\git_check
Copy-Item -Force D:\design_plans\KID_GUIDE.md D:\git_check\kids_guide.md
git status
git add kids_guide.md
git commit -m "Update kids guide"
git push
```

That is the normal flow:

```text
copy/edit file -> git status -> git add -> git commit -> git push
```

## 3. Upload a New File

Example: add a new file called `new_notes.md`.

```powershell
cd D:\git_check
Copy-Item -Force D:\design_plans\new_notes.md D:\git_check\new_notes.md
git status
git add new_notes.md
git commit -m "Add new notes"
git push
```

## 4. Upload a New Directory and Keep the Structure

Example: you have this folder:

```text
D:\design_plans\pnp_ip\lfsr_misr
```

You want it to appear in GitHub as:

```text
pnp_ip\lfsr_misr
```

Run:

```powershell
cd D:\git_check
New-Item -ItemType Directory -Force D:\git_check\pnp_ip | Out-Null
Copy-Item -Recurse -Force D:\design_plans\pnp_ip\lfsr_misr D:\git_check\pnp_ip\
git status
git add pnp_ip/lfsr_misr
git commit -m "Add lfsr misr design"
git push
```

Important: do not copy only the files if you want the folder structure. Copy the folder into the matching parent folder.

## 5. Upload Many Changed Files

If you already copied or edited many files inside `D:\git_check`, run:

```powershell
cd D:\git_check
git status
git add .
git commit -m "Update design files"
git push
```

Use `git add .` only when you really want to upload all changed files shown by `git status`.

## 6. What To Do If GitHub Asks Login

When you run:

```powershell
git push
```

GitHub may open a browser login window.

Do this:

1. Sign in to GitHub in that browser window.
2. Approve Git Credential Manager.
3. Come back to PowerShell.
4. The push should continue.

If PowerShell asks for username and password:

```text
Username: your GitHub username
Password: use a GitHub token, not your normal GitHub password
```

Do not paste your GitHub password into chat.

## 7. If Push Says Remote Has New Work

Sometimes GitHub has a change that your computer does not have yet.

Run:

```powershell
cd D:\git_check
git pull --rebase
git push
```

If Git says there is a conflict, stop and fix the conflict before pushing.

## 8. Check What Will Be Uploaded

Before commit:

```powershell
git status
git diff
```

After commit, to see the last commit:

```powershell
git log -1 --oneline
```

## 9. Perforce Similar Commands

Perforce is different from Git, but the idea is similar.

### Perforce Login

```powershell
p4 login
```

### See Changed Files

```powershell
p4 opened
```

### Add a New File

```powershell
p4 add path\to\new_file.sv
```

### Edit an Existing File

```powershell
p4 edit path\to\existing_file.sv
```

### Submit to Perforce

```powershell
p4 submit -d "Update design files"
```

### Reconcile a Whole Directory

This finds added, edited, and deleted files under a directory:

```powershell
p4 reconcile //depot/path/to/project/...
p4 submit -d "Update project files"
```

### Parallel Perforce Sync Example

This is useful when syncing many big files:

```powershell
p4 -Zparallel=threads=8 sync //depot/path/to/project/...
```

Use your real depot path instead of `//depot/path/to/project/...`.

## 10. Quick Memory

Git:

```powershell
git status
git add .
git commit -m "Message"
git push
```

Perforce:

```powershell
p4 reconcile //depot/path/...
p4 submit -d "Message"
```
