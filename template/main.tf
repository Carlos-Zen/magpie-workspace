terraform {
  required_providers {
    coder  = { source = "coder/coder", version = "~> 2.0" }
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

variable "workspace_cpus" {
  type        = string
  description = "CPU limit for each workspace, e.g. \"1\" or \"2\"."
  default     = "1"
}

variable "workspace_memory_mb" {
  type        = number
  description = "Memory limit for each workspace in MiB."
  default     = 2048
}

variable "magpie_share" {
  type        = string
  description = "Coder sharing level for the Magpie path app: owner, authenticated, or public. public requires CODER_DANGEROUS_ALLOW_PATH_APP_SHARING=true."
  default     = "owner"

  validation {
    condition     = contains(["owner", "authenticated", "public"], var.magpie_share)
    error_message = "magpie_share must be owner, authenticated, or public."
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

locals {
  app_base      = "/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}.main/apps/magpie/"
  public_origin = trimsuffix(data.coder_workspace.me.access_url, "/")
  web_key       = "magpie-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-web"
  gateway_key   = "magpie-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-gw"
}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  startup_script = <<-EOT
    set -e
    sudo chown coder:coder /home/coder
    sudo mkdir -p /home/coder/workspace /home/coder/workspace/.claude-config
    sudo chown -R coder:coder /home/coder/workspace
    export DISPLAY=:99
    /usr/local/bin/start-browser.sh
    /usr/local/bin/start-magpie.sh
    /usr/local/bin/start-magpie-proxy.sh
    echo "Workspace ready for ${data.coder_workspace_owner.me.name}"
    if command -v claude >/dev/null 2>&1; then claude --version || true; fi
  EOT
}

resource "coder_app" "browser" {
  agent_id     = coder_agent.main.id
  slug         = "browser"
  display_name = "Browser"
  url          = "http://localhost:6080"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:6080"
    interval  = 5
    threshold = 20
  }
}

resource "coder_app" "magpie" {
  agent_id     = coder_agent.main.id
  slug         = "magpie"
  display_name = "Magpie"
  url          = "http://localhost:3440"
  subdomain    = false
  share        = var.magpie_share
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-root-home"
}

resource "docker_volume" "workspace_home" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-home"
}

resource "docker_container" "workspace" {
  count   = data.coder_workspace.me.start_count
  image   = "coder-workspace:latest"
  name    = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  command = ["bash", "-lc", coder_agent.main.init_script]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "CLAUDE_CONFIG_DIR=/home/coder/workspace/.claude-config",
    "DISPLAY=:99",
    "MAGPIE_ADDR=0.0.0.0:3425",
    "MAGPIE_WEB_KEY=${local.web_key}",
    "MAGPIE_EXTERNAL_KEY=${local.gateway_key}",
    "MAGPIE_PUBLIC_ORIGIN=${local.public_origin}",
    "MAGPIE_PUBLIC_URL=${local.public_origin}${local.app_base}",
    "MAGPIE_WEB_URL=${local.public_origin}${local.app_base}?k=${local.web_key}",
    "CODER_APP_BASE=${local.app_base}",
  ]

  restart     = "unless-stopped"
  memory      = var.workspace_memory_mb
  memory_swap = var.workspace_memory_mb
  cpus        = var.workspace_cpus

  volumes {
    volume_name    = docker_volume.home.name
    container_path = "/home/coder"
  }
  volumes {
    volume_name    = docker_volume.workspace_home.name
    container_path = "/home/coder/workspace"
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id

  item {
    key   = "runtime"
    value = "Docker workspace"
  }
  item {
    key   = "claude_code"
    value = "installed; /usr/local/bin/claude is a shim that sets CLAUDE_CODE_ENTRYPOINT=custom"
  }
  item {
    key   = "home_persisted"
    value = "whole /home/coder volume"
  }
  item {
    key   = "visual_browser"
    value = "Chromium + noVNC"
  }
  item {
    key   = "magpie"
    value = "web + gateway (3430/3425), nginx path proxy (3440)"
  }
  item {
    key   = "magpie_url"
    value = "${local.public_origin}${local.app_base}?k=${local.web_key}"
  }
  item {
    key   = "magpie_gateway_url"
    value = "${local.public_origin}${local.app_base}v1"
  }
  item {
    key   = "magpie_gateway_key"
    value = local.gateway_key
  }
}
