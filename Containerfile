FROM alpine:3.20

# Add the Anthropic signing key and stable apk repository
RUN wget -O /etc/apk/keys/claude-code.rsa.pub \
         https://downloads.claude.ai/keys/claude-code.rsa.pub \
    && echo "https://downloads.claude.ai/claude-code/apk/stable" \
    >> /etc/apk/repositories

# Install Claude Code
RUN apk update && apk add --no-cache claude-code

# Create a non-root user and workspace
RUN adduser -D -u 1000 claude
USER claude
WORKDIR /workspace

ENTRYPOINT ["claude"]
