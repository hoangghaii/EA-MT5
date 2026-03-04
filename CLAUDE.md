# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Context

This repository contains an Expert Advisor (EA) for MetaTrader 5 (MT5), written in MQL5. The project uses the ClaudeKit Engineer agent orchestration framework to assist with planning, implementation, debugging, and documentation.

**Language**: MQL5 (.mq5 source → .ex5 compiled binary)
**Platform**: MetaTrader 5

## Directory Layout

```
/
├── src/            # MQL5 source files (.mq5, .mqh)
├── plans/          # Implementation plans and agent reports
│   └── reports/   # Agent-to-agent communication (YYMMDD-from-X-to-Y-task-report.md)
├── bugs/           # Bug reports and tracking
├── references/     # Reference materials (strategy docs, MQL5 API refs, notes)
└── docs/           # Project documentation (architecture, standards, roadmap)
```

## Build & Compile

MQL5 files are compiled using MetaEditor (bundled with MT5 terminal):

```bash
# On Windows via MetaEditor CLI
metaeditor64.exe /compile:"src/MyEA.mq5" /log

# Check compile log
cat src/MyEA.log
```

Compilation produces `.ex5` binaries. There is no traditional test runner — validation is done via MT5's **Strategy Tester** (backtesting) or forward testing on a demo account.

## Role & Responsibilities

Analyze user requirements, delegate tasks to appropriate sub-agents, and ensure cohesive delivery of features that meet specifications and architectural standards.

## Workflows

- Primary workflow: `./.claude/workflows/primary-workflow.md`
- Development rules: `./.claude/workflows/development-rules.md`
- Orchestration protocols: `./.claude/workflows/orchestration-protocol.md`
- Documentation management: `./.claude/workflows/documentation-management.md`

**IMPORTANT:** Analyze the skills catalog and activate the skills that are needed for the task during the process.
**IMPORTANT:** You must follow strictly the development rules in `./.claude/workflows/development-rules.md` file.
**IMPORTANT:** Before you plan or proceed any implementation, always read `./README.md` first to get context.
**IMPORTANT:** Sacrifice grammar for the sake of concision when writing reports.
**IMPORTANT:** In reports, list any unresolved questions at the end, if any.
**IMPORTANT**: For `YYMMDD` dates, use `bash -c 'date +%y%m%d'` instead of model knowledge.

## Agent Communication

Agents communicate via markdown reports saved to `./plans/<plan-name>/reports/`. Naming convention:

```
YYMMDD-from-[source-agent]-to-[dest-agent]-[task]-report.md
```

Example: `260304-from-planner-to-main-entry-logic-report.md`

## Documentation Management

Keep docs in `./docs/` and update them as code evolves:

```
./docs
├── project-overview-pdr.md
├── code-standards.md
├── codebase-summary.md
├── system-architecture.md
└── project-roadmap.md
```

**IMPORTANT:** *MUST READ* and *MUST COMPLY* all *INSTRUCTIONS* in `./CLAUDE.md`, especially *WORKFLOWS* — this is *MANDATORY. NON-NEGOTIABLE. NO EXCEPTIONS.*
