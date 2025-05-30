# zblocks

A simple status bar for dwm written in Zig.

## Features

- CPU load average
- Memory usage percentage  
- Battery percentage
- Date and time

## Requirements

- Zig compiler
- X11 (xsetroot)
- Linux with /proc and /sys filesystems

## Installation

```
zig build-exe zblocks.zig -O ReleaseFast
cp zblocks /usr/local/bin/
```

## Usage

Add to your .xinitrc:

```
zblocks &
```

## Configuration

Edit the source code and recompile.

## Customization

Modify these functions to change what's displayed:
- `getCpuLoad()` - CPU load from /proc/loadavg
- `getMemoryInfo()` - Memory usage from /proc/meminfo  
- `getBatteryPercentage()` - Battery from /sys/class/power_supply/BAT0/capacity
- `getDateTime()` - Current date and time

Change separators in the `addBlock()` calls in `main()`.

## Notes

- Updates every second
- Minimal memory allocations
- No configuration files
- No dependencies except libc
