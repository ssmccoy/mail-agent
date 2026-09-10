# Trusted runtime paths. Source this file before using mail-agent helpers.
# Environment overrides belong to the invoking account or service configuration,
# never to a phase request or a repository's configuration.

MAIL_AGENT_LIB=${MAIL_AGENT_LIB:-$HOME/lib/mail-agent}
MAIL_AGENT_BIN=${MAIL_AGENT_BIN:-$HOME/bin}
MAIL_AGENT_CONFIG=${MAIL_AGENT_CONFIG:-$HOME/.config/mail-agent}
MAIL_AGENT_PROFILES=${MAIL_AGENT_PROFILES:-$HOME/.config/landlock}
MAIL_AGENT_LANDLOCK=${MAIL_AGENT_LANDLOCK:-$HOME/bin/landlock}
MAIL_AGENT_REPOSITORIES=${MAIL_AGENT_REPOSITORIES:-$HOME/mail/.agent/repos}
MAIL_AGENT_TOOLCHAIN=${MAIL_AGENT_TOOLCHAIN:-$HOME/.proto}
MAIL_AGENT_TOOLCHAIN_CONFIG=${MAIL_AGENT_TOOLCHAIN_CONFIG:-$HOME/.prototools}
MAIL_AGENT_EXEC_PATH=${MAIL_AGENT_EXEC_PATH:-$MAIL_AGENT_TOOLCHAIN/shims:$MAIL_AGENT_TOOLCHAIN/bin:/usr/bin}
MAIL_AGENT_GO_CACHE=${MAIL_AGENT_GO_CACHE:-$HOME/mail/.agent/go}
MAIL_AGENT_GIT_CONFIG=${MAIL_AGENT_GIT_CONFIG:-$HOME/.config/git}
MAIL_AGENT_INSTRUCTIONS=${MAIL_AGENT_INSTRUCTIONS:-$HOME/.claude/CLAUDE.md}

export MAIL_AGENT_LIB MAIL_AGENT_BIN MAIL_AGENT_CONFIG MAIL_AGENT_PROFILES MAIL_AGENT_LANDLOCK
export MAIL_AGENT_REPOSITORIES MAIL_AGENT_TOOLCHAIN MAIL_AGENT_TOOLCHAIN_CONFIG
export MAIL_AGENT_EXEC_PATH MAIL_AGENT_GO_CACHE MAIL_AGENT_GIT_CONFIG MAIL_AGENT_INSTRUCTIONS

# Keep trusted helpers independent of project/toolchain command lookup. The
# inner profiles pass MAIL_AGENT_EXEC_PATH to the workload after confinement.
if [ -n "${MAIL_AGENT_SYSTEM_SHARED:-}" ]; then
    PATH=/usr/local/bin:/usr/bin:/bin

    export PATH
fi

mail_agent_runtime() {
    case "$1" in
        claude)
            MAIL_AGENT_PACKAGES=${MAIL_AGENT_PACKAGES:-$HOME/.local/share/claude}
            MAIL_AGENT_SHARED_STATE=${MAIL_AGENT_SHARED_STATE:-$HOME/mail/.agent/claude}
            MAIL_AGENT_AUTH=${MAIL_AGENT_AUTH:-$HOME/.claude/.credentials.json}
            ;;
        codex)
            MAIL_AGENT_PACKAGES=${MAIL_AGENT_PACKAGES:-$HOME/.codex/packages}
            MAIL_AGENT_SHARED_STATE=${MAIL_AGENT_SHARED_STATE:-$HOME/mail/.agent/codex}
            MAIL_AGENT_AUTH=${MAIL_AGENT_AUTH:-$HOME/.codex/auth.json}
            ;;
        pi)
            MAIL_AGENT_PACKAGES=${MAIL_AGENT_PACKAGES:-$HOME/.local/lib/node_modules/@earendil-works/pi-coding-agent}
            MAIL_AGENT_SHARED_STATE=${MAIL_AGENT_SHARED_STATE:-$HOME/.pi/agent}
            MAIL_AGENT_AUTH=${MAIL_AGENT_AUTH:-$HOME/.pi/agent/auth.json}
            ;;
        *) return 64 ;;
    esac

    MAIL_AGENT_EXECUTABLE=${MAIL_AGENT_EXECUTABLE:-$HOME/.local/bin/$1}

    export MAIL_AGENT_EXECUTABLE MAIL_AGENT_PACKAGES MAIL_AGENT_SHARED_STATE MAIL_AGENT_AUTH
}
