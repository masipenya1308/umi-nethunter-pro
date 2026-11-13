# План и состояние порта (2026-11-13)

Заготовка собрана, но **ни один образ отсюда ещё не собирался и не прошивался**.
Всё, что ниже помечено «проверено», проверено в `umi-mainline` на этом же
устройстве, а не здесь.

## Проверенные факты (не переоткрывать)

| Факт | Где доказано |
|---|---|
| Ядро 6.12 грузится в userspace за ~12 с, экран 1080×2340, яркость, blank/unblank | `umi-mainline/README.md`, `docs/DISPLAY.md` |
| Сенсор ST FTS на `i2c13`/0x49 работает (нужен boost PM8150B GPIO5) | `docs/TOUCH.md` §12 |
| Adreno 650, Wi-Fi QCA6390, зарядка/быстрый заряд, KDE Plasma — работают | `README.md`, `GPU.md`, `WIFI.md`, `BATTERY.md` |
| `fastboot boot` работает и ничего не пишет; **один раз за сеанс загрузчика** | `ARCH-ROOTFS.md` §5.1 |
| ABL требует gzip-ядро и `base = 0`; `header_version 2`, DTB в dtb-сегменте, `dtb_size != 0` | `tools/pack-umi.py`, `ARCH-ROOTFS.md` §9 |
| DTB обязан нести `qcom,msm-id = <356 0x10000>`, `qcom,board-id = <43 0>` | `pack-umi.py` + `tools/dtb.py` |
| Корень живёт на `/dev/sda34` = `userdata` (226 ГиБ), ext4, заполняется образом с префиксом | `ARCH-ROOTFS.md` §2–3 |
| `CONFIG_CMDLINE_FORCE=y`: cmdline из boot.img игнорируется, работает зашитый в `Image` | `config/umi.config` |

**Противоречие в старых заметках.** `umi-nethunter/docs/STATE.md` (30.10)
утверждает, что `fastboot boot` не поддерживается и что USB-консоль не
поднимается. `umi-mainline` (11.11) грузится именно через `fastboot boot` и
имеет рабочий экран. Считаем верным второе; если на конкретном экземпляре
`fastboot boot` ответит `Failed to load/authenticate boot image` — значит
прошивка ABL другая, тогда `fastboot flash boot` + `fastboot reboot`.

## Что меняет этот репозиторий в картине мира

1. **cmdline.** Kali грузится штатным initramfs-tools и ищет корень по
   `root=UUID=...` из boot.img. `CMDLINE_FORCE=y` этот аргумент выбрасывает, и
   загрузка молча уходит в «не могу смонтировать корень». На arm64 это не
   флаг «extend», а `choice`, поэтому дельта ставит
   `CONFIG_CMDLINE_FROM_BOOTLOADER=y`, а всё, что umi нужно от ядра
   (`pd_ignore_unused`, `clk_ignore_unused`, `regulator_ignore_unused`,
   `arm-smmu.disable_bypass=0`, `console=`), перенесено в `append` из
   `sm8250.toml`. Без этих четырёх параметров панель/сенсор отваливаются
   (см. `docs/BUILD.md` в umi-mainline).
2. **Не `-support` пакет.** `sm8250-support` в репозиториях Kali/Mobian нет
   (есть sdm845/sm7150/...). Вариант `sm8250` поэтому идёт веткой `wip`:
   `qcom-support-common` + ядро нашим пакетом. Если появится настоящий
   `sm8250-support` — убрать `sm8250` из условия в `packages-base.yaml`.
3. **Размер ramdisk.** У `bootloader.sh` нет ограничения, а у ABL umi — есть.
   `MODULES=dep` + `COMPRESS=gzip` (патч 0002) держат initramfs в единицах МБ;
   UFS и ext4 в этом ядре собраны в `Image`, так что больше ничего не нужно.

## Лестница тестов

**M0. Ядро из пакета грузится с rootfs.** Критерий: на экране fbcon виден
dmesg, `systemd` доходит до `kali login:` (или до приглашения на tty0).

1. `sh kernel/build-kernel-deb.sh` → в логе все `OK CONFIG_...`.
2. `sh nethunter/apply.sh ../kali-nethunter-pro` → патчи применились.
3. `./build.sh -a arm64 -v sm8250 -D phosh` → в `output/` есть `*.rootfs.img`
   и `*.boot-umi-wifi.img`.
4. Прошить `userdata` + `boot`, затем `fastboot boot`.
5. Если чёрный экран: сначала `fastboot boot` **нативного** образа
   umi-mainline (`out/boot-umi.img`) — это две минуты и отсекает весь класс
   «ABL/упаковка», до того как копать ядро.

**M1. Ввод и рабочий стол.** Тач, Phosh, поворот. Если тач мёртв — проверить
`vdd_boost` (PM8150B GPIO5) в DTB: это единственная известная причина.

**M2. GPU/сеть.** Прошивки `a650_*` кладутся в `/lib/firmware/qcom/` образа
(в umi-mainline они в initramfs, здесь — в rootfs), драйвер freedreno
`=m` + `modules-load.d`. Wi-Fi: `ath11k`, MAC уже закреплён в DTB.

**M3. Отладка без провода.** USB-gadget консоль (CDC-ACM/RNDIS) штатным
initramfs Kali не поднимается — это отдельная работа из `umi-nethunter`.
До неё единственный канал — экран (fbcon).

## Открытые неизвестные (по убыванию цены ошибки)

1. `make bindeb-pkg` при кросс-сборке: путь упаковки в mainline рабочий, но
   никем здесь не проверялся. Если падает — `make install
   INSTALL_PATH=<mnt>/boot` + `modules_install` в примонтированный rootfs
   образа, дальше `bootloader.sh` работает так же (ему нужны только
   `/boot/vmlinuz-<ver>` и `/lib/modules/<ver>`).
2. `vmlinuz` из Debian-пакета на arm64 — это `Image.gz`. ABL требует gzip;
   если в конкретной сборке окажется zstd/xz, будет чёрный экран и возврат в
   fastboot. Проверяется `file /boot/vmlinuz-*` в образе.
3. `MODULES=dep`: initramfs-tools должен увидеть корень по UUID. Если initrd
   окажется без ufs/ext4 — вернуть `MODULES=most` и ужать чем-то другим.
4. `variant = "wifi"` в toml — это способ заставить `bootloader.sh` выбрать
   `sm8250-xiaomi-umi-wifi.dtb` (полный DTB umi). Побочный эффект:
   в cmdline попадает `mobile.variant=wifi`. Косметика, но если
   droid-juicer/аудио начнут искать `umi-wifi` — знать, где искать причину.
5. `systemd-growfs` на `/`: fstab несёт `x-systemd.growfs`, а раздел 226 ГиБ
   против образа 8 ГБ. Ожидаем авто-расширение на первом старте; если нет —
   `resize2fs /dev/sda34` вручную.
6. `ramoops`/pstore в `sm8250-xiaomi-umi-wifi.dtb` не подтверждён. Пока экран
   работает, это не нужно; если экран умрёт — добавить узел (адрес окна
   `0xb0000000`, 4 МиБ, как в `umi-nethunter`).

## Откат

`userdata` перезаписывается один раз и навсегда (данные MIUI). Всё остальное
возвращается:

```sh
fastboot flash boot   D:\umi\backups\pre-flash-20261027\boot-before-flash.img
fastboot flash dtbo   D:\umi\backups\pre-stock\dtbo.img
fastboot flash vbmeta D:\umi\backups\pre-stock\vbmeta.img
```

`fastboot flash cache` (356 МБ) — дешёвый полигон для проверки `switch_root`
до того, как трогать `userdata`; приём описан в `ARCH-ROOTFS.md` §5.2.
