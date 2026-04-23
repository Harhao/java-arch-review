---
description: "对当前 Java/Spring Boot 项目执行架构设计审查，覆盖 19 个核心维度（安全、性能、分层、测试等）。支持 Full/PR/Focus/Quick 四种模式。"
---

请使用 java-server-arch-review skill 对当前项目执行架构审查。

审查模式由用户指定，默认使用 PR 模式（仅扫描变更文件涉及的维度）。如果用户提供了额外参数（如"全量"、"只看安全"、"quick"），按对应模式执行。

$ARGUMENTS
