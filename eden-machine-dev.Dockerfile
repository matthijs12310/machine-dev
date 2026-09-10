# Pre-baked Eden image: linuxserver/eden + first-boot fixes so cold
# boots come up streaming with zero manual steps. Contains NO keys,
# firmware or ROMs (those come from /nas at boot via 99-emu-setup.sh).
FROM lscr.io/linuxserver/eden:latest

COPY docker/99-emu-setup.sh /custom-cont-init.d/99-emu-setup.sh
RUN chmod +x /custom-cont-init.d/99-emu-setup.sh
