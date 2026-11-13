# umi-nethunter-pro

Заготовка порта **Kali NetHunter Pro** на Xiaomi Mi 10 (`umi`, SM8250 / kona,
M2001J2C). Здесь нет ни ядра, ни rootfs — это клей между двумя вещами, которые
уже существуют и работают по отдельности:

| Что | Откуда | Состояние |
|---|---|---|
| Ядро, device tree, панель, сенсор, GPU, Wi-Fi, зарядка | [umi-mainline](../umi-mainline) | работает на устройстве, см. его `README.md`/`TESTLOG.md` |
| Rootfs, Phosh, инструменты Kali | [kali-nethunter-pro](https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-pro) | официальный билдер, umi в нём нет |

Официальная сборка NetHunter Pro для Qualcomm устроена так: debos собирает
rootfs, ставит пакет `<soc>-support`, кладёт в образ готовый kernel package и
вызывает `devices/qcom/bootloader.sh`, который берёт
`/boot/vmlinuz-<ver>` + `/usr/lib/linux-image-<ver>/qcom/<soc>-<vendor>-<model>.dtb`
и собирает Android boot.img. Для umi не хватает ровно трёх вещей, и все они тут:

1. варианта `sm8250` в `build.sh` (иначе билдер не знает такого устройства);
2. `devices/qcom/configs/sm8250.toml` — адреса загрузки, `header_version 2`,
   DTB в dtb-сегменте, cmdline, который переживает ABL;
3. kernel package из umi-mainline с DTB на том месте, где его ищет
   `bootloader.sh`, плюс правка конфигурации ядра, без которой Kali не найдёт
   свой корень (см. `kernel/umi-nethunter.config`).

Патчи в `nethunter/patches/` сгенерированы против текущего `main` билдера
(2026-11). Если upstream уедет — `apply.sh` скажет, что патч не лёг.

## Быстрый старт (Linux-хост)

```sh
# 0. рядом должны лежать оба репозитория
git clone https://github.com/masipenya1308/umi-mainline.git
git clone https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-pro.git

# 1. ядро -> kernel/out/linux-image-*.deb  (долго: два прохода сборки)
sh kernel/build-kernel-deb.sh

# 2. патчи + пакет в дерево билдера
sh nethunter/apply.sh ../kali-nethunter-pro

# 3. образ rootfs + boot.img (debos, KVM, ~50 ГБ места)
cd ../kali-nethunter-pro
./build.sh -a arm64 -v sm8250 -D phosh
```

Результат в `output/`: `kali-nethunterpro-*-sm8250-phosh-arm64.rootfs.img` и
`*.boot-umi-wifi.img`.

## Прошивка и первый запуск

```sh
fastboot getvar current-slot           # A-only, но пусть будет в логе
fastboot flash userdata output/*.rootfs.img     # ЭТО СТИРАЕТ ДАННЫЕ
fastboot flash boot     output/*.boot-umi-wifi.img
fastboot boot           output/*.boot-umi-wifi.img   # не reboot
```

`fastboot boot` (а не `reboot`) — потому что после `reboot` этот ABL падает
обратно в fastboot, а `fastboot boot` поднимает ту же картинку сразу.
В одном сеансе загрузчика `fastboot boot` работает **один раз**.

Откат:

```sh
fastboot flash boot D:\umi\backups\pre-flash-20261027\boot-before-flash.img
fastboot flash dtbo D:\umi\backups\pre-stock\dtbo.img
fastboot flash vbmeta D:\umi\backups\pre-stock\vbmeta.img
```

## Что где лежит

```
kernel/umi-nethunter.config     дельта к config/umi.config из umi-mainline
kernel/build-kernel-deb.sh      ядро + DTB -> Debian linux-image package
nethunter/patches/              три патча к официальному билдеру
nethunter/apply.sh              накатить патчи + положить пакет ядра
docs/PLAN.md                    что проверено, что нет, порядок экспериментов
```

Документация по самому железу не дублируется: она в `umi-mainline/docs/`
(`DISPLAY.md`, `TOUCH.md`, `GPU.md`, `WIFI.md`, `ARCH-ROOTFS.md`).

## Лицензия

`kernel/`, `nethunter/` — CC0-1.0. `docs/` — CC-BY-4.0. Патчи к
kali-nethunter-pro сохраняют его лицензию (GPL-3.0).
