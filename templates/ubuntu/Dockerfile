FROM ubuntu:22.04 

RUN rm -rf /var/lib/apt/lists/* && apt-get update && apt-get upgrade -y && apt-get install --yes bash curl make sudo

ARG USER=coder

RUN userdel ${USER} || true
RUN useradd --groups sudo --no-create-home --shell /bin/bash ${USER} \
    && echo "${USER} ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USER} \
    && chmod 0440 /etc/sudoers.d/${USER}

USER ${USER}
WORKDIR /home/${USER}

COPY fxdev.sh /usr/local/bin/fxd
RUN chmod +x /usr/local/bin/fxd

