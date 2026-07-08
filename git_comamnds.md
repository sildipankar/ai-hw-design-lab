# Git and Perforce Commands Cheat Sheet

This file is for simple copy-paste commands.

Your local Git repo folder:

```powershell
D:\git_check
```

Your GitHub repo:

```text
https://github.com/sildipankar/ai-hw-design-lab
```

Important rule:

```text
git add    = prepare file locally
git commit = save version locally
git push   = publish to GitHub
```

If you want everything to remain local, do not run `git push`.

For Perforce:

```text
p4 edit / p4 add / p4 reconcile = prepare file locally in changelist
p4 submit                       = publish to Perforce server
```

If you want everything to remain local in Perforce, do not run `p4 submit`.

## 1. Check Status Before Work

Git:

```powershell
cd D:\git_check
git status
```

Perforce:

```powershell
cd D:\your_p4_workspace
p4 info
p4 opened
```

Meaning:

```text
git status = what changed in Git
p4 opened  = what files are open in Perforce
```

## 2. Login

Git:

```powershell
git push
```

If GitHub asks for login, a browser window may open. Sign in there. Do not type your GitHub password into chat.

If PowerShell asks for credentials:

```text
Username: your GitHub username
Password: GitHub token, not normal password
```

Perforce:

```powershell
p4 login
```

Then type your Perforce password when the terminal asks.

## 3. Update One Existing File

Example: `D:\design_plans\KID_GUIDE.md` changed, and you want to update `kids_guide.md` in this repo.

Git:

```powershell
cd D:\git_check
Copy-Item -Force D:\design_plans\KID_GUIDE.md D:\git_check\kids_guide.md
git status
git add kids_guide.md
git commit -m "Update kids guide"
```

Stop here if you want local only.

Publish to GitHub only when ready:

```powershell
git push
```

Perforce:

```powershell
cd D:\your_p4_workspace
p4 edit path\to\kids_guide.md
Copy-Item -Force D:\design_plans\KID_GUIDE.md path\to\kids_guide.md
p4 opened
p4 diff path\to\kids_guide.md
```

Stop here if you want local only.

Publish to Perforce only when ready:

```powershell
p4 submit -d "Update kids guide"
```

## 4. Add One New File

Example: add `new_notes.md`.

Git:

```powershell
cd D:\git_check
Copy-Item -Force D:\design_plans\new_notes.md D:\git_check\new_notes.md
git status
git add new_notes.md
git commit -m "Add new notes"
```

Publish only when ready:

```powershell
git push
```

Perforce:

```powershell
cd D:\your_p4_workspace
Copy-Item -Force D:\design_plans\new_notes.md path\to\new_notes.md
p4 add path\to\new_notes.md
p4 opened
```

Publish only when ready:

```powershell
p4 submit -d "Add new notes"
```

## 5. Add a New Directory and Keep Structure

Example source folder:

```text
D:\design_plans\pnp_ip\lfsr_misr
```

You want GitHub or Perforce to keep this structure:

```text
pnp_ip\lfsr_misr
```

Git:

```powershell
cd D:\git_check
New-Item -ItemType Directory -Force D:\git_check\pnp_ip | Out-Null
Copy-Item -Recurse -Force D:\design_plans\pnp_ip\lfsr_misr D:\git_check\pnp_ip\
git status
git add pnp_ip/lfsr_misr
git commit -m "Add lfsr misr design"
```

Publish only when ready:

```powershell
git push
```

Perforce:

```powershell
cd D:\your_p4_workspace
New-Item -ItemType Directory -Force path\to\pnp_ip | Out-Null
Copy-Item -Recurse -Force D:\design_plans\pnp_ip\lfsr_misr path\to\pnp_ip\
p4 reconcile path\to\pnp_ip\lfsr_misr\...
p4 opened
```

Publish only when ready:

```powershell
p4 submit -d "Add lfsr misr design"
```

Key idea:

```text
Copy the folder into the matching parent folder.
Do not flatten the files.
```

## 6. Update Many Files

Use this only when you looked at `git status` or `p4 opened` and agree with all changes.

Git:

```powershell
cd D:\git_check
git status
git add .
git commit -m "Update design files"
```

Publish only when ready:

```powershell
git push
```

Perforce:

```powershell
cd D:\your_p4_workspace
p4 reconcile path\to\project\...
p4 opened
```

Publish only when ready:

```powershell
p4 submit -d "Update design files"
```

## 7. Review Before Publishing

Git:

```powershell
cd D:\git_check
git status
git diff
git diff --staged
git log -1 --oneline
```

Perforce:

```powershell
cd D:\your_p4_workspace
p4 opened
p4 diff
p4 describe -s pending_changelist_number
```

## 8. If GitHub Has New Files First

If `git push` says the remote has new work, run:

```powershell
cd D:\git_check
git pull --rebase
git push
```

Perforce equivalent is sync first:

```powershell
cd D:\your_p4_workspace
p4 sync
```

## 9. Parallel Perforce Sync

Use this when syncing a large Perforce depot path:

```powershell
p4 -Zparallel=threads=8 sync //depot/path/to/project/...
```

Example with a client workspace path:

```powershell
p4 -Zparallel=threads=8 sync path\to\project\...
```

Use your real depot path or workspace path.

## 10. Quick Memory

Git local only:

```powershell
git status
git add .
git commit -m "Message"
```

Git publish:

```powershell
git push
```

Perforce local only:

```powershell
p4 reconcile path\to\project\...
p4 opened
```

Perforce publish:

```powershell
p4 submit -d "Message"
```
