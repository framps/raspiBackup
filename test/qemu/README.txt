The qemu setup was done accoriding the instructions available on https://crycode.de/raspberry-pi-4-emulieren-mit-qemu/

Steps to build regressionenvironment:
1) Execute build-qemu-kernel.sh
2) Execute rpi-emu-create-image.sh
3) Execute ../rpi-emu-start.sh Bookworm.qcow2
4) Login into image and wait until new image finished all initial setup steps
5) cd ..
6) Adapt env.defs to you environment
7) scp your pub user ssh credential to the image user pi
8) scp your root user ssh credential to the image user pi
9) copy the pi authorized_keys to root on the image

