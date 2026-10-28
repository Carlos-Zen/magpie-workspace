# syntax=docker/dockerfile:1

# Magpie is copied from its official image; the workspace itself is Debian
# based because Chromium/noVNC and the Claude Code CLI need the usual system
# libraries.
FROM ghcr.io/yetone/magpie:latest AS magpie

FROM node:22-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git sudo openssh-client ca-certificates curl ripgrep procps less vim-tiny \
      chromium xvfb fluxbox x11vnc novnc websockify xclip python3 nginx \
      fonts-liberation fonts-noto fonts-noto-cjk fonts-noto-color-emoji \
      dbus-x11 x11-utils \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash coder \
 && echo 'coder ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/coder

# Latest Claude Code, plus a shim on the `claude` path. The shim forces the
# custom entrypoint before handing over to the real CLI.
RUN npm install -g @anthropic-ai/claude-code@latest \
 && mv /usr/local/bin/claude /usr/local/bin/claude-real \
 && printf '%s\n' \
      '#!/bin/sh' \
      'export CLAUDE_CODE_ENTRYPOINT=custom' \
      'exec /usr/local/bin/claude-real "$@"' \
      >/usr/local/bin/claude \
 && chmod 0755 /usr/local/bin/claude

# noVNC + clipboard bridge
RUN ln -s /usr/share/novnc/vnc.html /usr/share/novnc/index.html
COPY novnc-bootstrap.js /usr/share/novnc/novnc-bootstrap.js
COPY patch-novnc-clipboard.py /tmp/patch-novnc-clipboard.py
RUN python3 /tmp/patch-novnc-clipboard.py \
 && rm /tmp/patch-novnc-clipboard.py
RUN sed -i '/<script type="module"/i <script src="novnc-bootstrap.js"></script>' /usr/share/novnc/vnc.html \
 && sed -i 's|src="novnc-bootstrap.js"|src="novnc-bootstrap.js?v=7"|' /usr/share/novnc/vnc.html \
 && sed -i 's|src="app/ui.js"|src="app/ui.js?v=7"|' /usr/share/novnc/vnc.html

# Workspace helpers
COPY start-browser.sh /usr/local/bin/start-browser.sh
COPY start-magpie.sh /usr/local/bin/start-magpie.sh
COPY start-magpie-proxy.sh /usr/local/bin/start-magpie-proxy.sh
RUN chmod 0755 \
      /usr/local/bin/start-browser.sh \
      /usr/local/bin/start-magpie.sh \
      /usr/local/bin/start-magpie-proxy.sh

# Magpie web + gateway binary (static Go build from the official image).
COPY --from=magpie /magpie /usr/local/bin/magpie

USER coder
WORKDIR /home/coder/workspace
ENV HOME=/home/coder
ENV DISPLAY=:99
EXPOSE 6080 3430 3440
CMD ["bash"]
