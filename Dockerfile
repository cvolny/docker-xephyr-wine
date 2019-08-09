from fedora:30
RUN dnf install -y wine
CMD wine explorer.exe
