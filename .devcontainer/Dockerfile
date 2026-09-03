FROM mcr.microsoft.com/devcontainers/ruby:4-4.0-trixie

# Install Rails
RUN su vscode -c "gem install rails"
RUN groupadd --system rubygems \
	&& usermod --append --groups rubygems vscode \
	&& chgrp -R rubygems "$GEM_HOME" \
	&& chmod -R g+rwX "$GEM_HOME" \
	&& find "$GEM_HOME" -type d -exec chmod g+s {} +

# Install Codex CLI independently from the user persistent state directory.
# Keeping the package under /opt prevents the /home/vscode/.codex volume from
# hiding the executable after the container is recreated.
RUN mkdir -p /opt/codex /home/vscode/.codex \
	&& if curl -fsSL https://chatgpt.com/codex/install.sh \
		| CODEX_NON_INTERACTIVE=1 \
		  CODEX_HOME=/opt/codex \
		  CODEX_INSTALL_DIR=/usr/local/bin \
		  sh \
		&& test -x /usr/local/bin/codex \
		&& /usr/local/bin/codex --version; then \
			echo "Codex CLI installed successfully."; \
		else \
			echo "WARNING: Codex CLI installation failed; continuing without Codex." >&2; \
		fi \
	&& chown -R vscode:vscode /home/vscode/.codex

# Default value to allow debug server to serve content over GitHub Codespace's port forwarding service
# The value is a comma-separated list of allowed domains 
ENV RAILS_DEVELOPMENT_HOSTS=".githubpreview.dev,.preview.app.github.dev,.app.github.dev"

# [Optional] Uncomment this section to install additional OS packages.
# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends <your-package-list-here>

# [Optional] Uncomment this line to install additional gems.
# RUN su vscode -c "gem install <your-gem-names-here>"

# [Optional] Uncomment this line to install global node packages.
# RUN su vscode -c "source /usr/local/share/nvm/nvm.sh && npm install -g <your-package-here>" 2>&1
