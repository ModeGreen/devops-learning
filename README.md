# DevOps Learning Log

My hands-on journey to becoming a DevOps engineer, following the [roadmap.sh DevOps path](https://roadmap.sh/devops).

Every exercise, script and small project from my learning lives here, committed as I go.

## Environment

- Windows 11 + WSL2 (Ubuntu)
- Python 3
- Git
- VS Code with the WSL extension

## Structure

| Folder | Topic |
|---|---|
| `day1/` | Linux terminal basics: navigation, files and directories, output redirection |
| `day2/` | Python basics: variables, types, user input, f-strings, conditionals |

## Highlights

### `day2/disk_v2.py` — disk usage checker

A small CLI script that reports disk usage for a server and assigns a status:

- **OK** — below 75%
- **WARNING** — 75% and above
- **CRITICAL** — 90% and above

It validates input (capacity must be positive, used space must be within capacity) and exits with code `1` on invalid data, so it can be used in automation.

```bash
python3 day2/disk_v2.py
```

## Progress

- [x] Development environment (WSL2, VS Code, Git)
- [x] Linux terminal basics
- [x] Python: variables, types, conditionals
- [ ] Python: loops, functions, files, error handling
- [ ] Git & GitHub workflow
- [ ] Bash scripting
- [ ] Networking, SSH, Nginx
- [ ] Docker
- [ ] CI/CD (GitHub Actions)
- [ ] Cloud & Infrastructure as Code (Terraform, Ansible)
- [ ] Monitoring (Prometheus, Grafana)