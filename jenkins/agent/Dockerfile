FROM docker:29.8.1-cli@sha256:018edbc908e08fcc9dbf029c812c34251e9b4719e6f71ca0e5eae2a987d014ca AS docker-cli

FROM jenkins/ssh-agent:9.0.0-jdk21@sha256:4609eba9f086fc7321de8e40e217601158280d5bd21160b9ed6e6e5218936c1c
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx
