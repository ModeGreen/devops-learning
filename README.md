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
| `day3/` | Python loops and collections: checking multiple servers, Nagios exit codes (tasks 4–5) |
| `day4/` | Python functions with tests, reading server lists from files, writing a report log (tasks 6–7) |
| `day5/` | Python modules: real disk usage via `shutil`, thresholds from environment variables, `pathlib`, `subprocess` (task 8) |
| `day6/` | Python error handling with `try/except`; web server access log analysis (tasks 9–10) |
| `day7/` | Linux: managing files and directories, viewing logs with `cat`, `less`, `head`, `tail` (tasks 11–12) |
| `day8/` | Editing configs in `nano`; Python `venv`, `pip` and YAML config validation (tasks 13–14) |
| `day9/` | Linux file permissions with `chmod` (task 15) |
| `day10/` | Python and the GitHub REST API: `requests`, JSON (task 16) |
| `day11/` | Linux users, groups, `sudo`, `chown`: a system user for a service (task 17) |
| `day12/` | Searching files and logs with `grep` and `find` (task 18) |
| `day13/` | Git branches, merges and conflict resolution; debugging a buggy Python script (tasks 19–20) |
| `day14/` | Output redirection and pipes: log reports with `cut`, `sort`, `uniq` (task 21) |
| `day15/` | Linux processes: `ps`, `pgrep`, `top`, `kill` and signals (task 22) |

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
- [x] Python: loops, functions, files, error handling
- [x] Python: virtual environments, YAML configs, REST APIs
- [x] Linux: permissions, users and groups, search, pipes, processes
- [ ] Git & GitHub workflow (branches and merges done, pull requests in progress)
- [ ] Bash scripting
- [ ] Networking, SSH, Nginx
- [ ] Docker
- [ ] CI/CD (GitHub Actions)
- [ ] Cloud & Infrastructure as Code (Terraform, Ansible)
- [ ] Monitoring (Prometheus, Grafana)
