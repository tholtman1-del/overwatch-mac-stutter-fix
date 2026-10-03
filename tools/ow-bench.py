#!/usr/bin/env python3
"""Summarise DXMT frame-time logs (DXMT_FRAMETIME_LOG, one frame time in ms per line).

Usage: ow-bench.py [--skip S] [--len S] [--timeline] LOG...
  --skip S    ignore the first S seconds (menus / loading)
  --len S     only use S seconds after the skip
  --timeline  also print avg FPS and hitches per 30 s window (to find the part to compare)
Hitches = single frames over 50 ms / 100 ms; these are the shader-compile stutters.
"""
import argparse, os, statistics


def load(path):
    with open(path) as f:
        return [float(line) for line in f if line.strip()]


def window(times, skip, length):
    t, out = 0.0, []
    for ms in times:
        t += ms / 1000
        if t < skip:
            continue
        if length and t > skip + length:
            break
        out.append(ms)
    return out


def summary(times):
    total = sum(times) / 1000
    worst = sorted(times, reverse=True)
    low = lambda frac: 1000 / statistics.mean(worst[:max(1, int(len(times) * frac))])
    h50 = sum(ms > 50 for ms in times)
    return {
        'secs': total, 'frames': len(times), 'avg': len(times) / total,
        'median': 1000 / statistics.median(times), 'low1': low(0.01), 'low01': low(0.001),
        'h50': h50, 'h100': sum(ms > 100 for ms in times), 'h50pm': h50 / total * 60, 'worst': worst[0],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('logs', nargs='+')
    ap.add_argument('--skip', type=float, default=0)
    ap.add_argument('--len', type=float, default=0)
    ap.add_argument('--timeline', action='store_true')
    a = ap.parse_args()
    print(f"{'run':38} {'secs':>5} {'avg':>6} {'med':>6} {'1%low':>6} {'.1%low':>6} "
          f"{'>50ms':>6} {'>100ms':>6} {'/min':>5} {'worst':>7}")
    for path in a.logs:
        times = window(load(path), a.skip, a.len)
        if len(times) < 2:
            print(f"{os.path.basename(path)[:38]:38} (no frames)")
            continue
        s = summary(times)
        print(f"{os.path.basename(path)[:38]:38} {s['secs']:5.0f} {s['avg']:6.1f} {s['median']:6.1f} "
              f"{s['low1']:6.1f} {s['low01']:6.1f} {s['h50']:6d} {s['h100']:6d} {s['h50pm']:5.1f} "
              f"{s['worst']:6.0f}ms")
        if a.timeline:
            t, chunk = 0.0, []
            for ms in times:
                chunk.append(ms)
                if sum(chunk) >= 30000:
                    print(f"    {t:5.0f}s  {len(chunk) / sum(chunk) * 1000:6.1f} fps  "
                          f"{sum(x > 50 for x in chunk):3d} hitches  worst {max(chunk):5.0f}ms")
                    t += sum(chunk) / 1000
                    chunk = []


if __name__ == '__main__':
    main()
