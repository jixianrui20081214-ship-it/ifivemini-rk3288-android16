#!/usr/bin/env python3
"""patch-delegate.py <ThemedIconDelegate.smali>

Rewrites, in place, the baksmali output of
com.android.launcher3.icons.mono.ThemedIconDelegate:
  - adds the field  cache:Lcom/android/launcher3/icons/mono/ThemedIconCache;
  - creates it in the constructor, right after Object.<init>
  - replaces the body of drawContent() with a call to ThemedIconCache.draw()

Every anchor must match exactly once; otherwise the script stops and leaves the file alone.
"""
import re
import sys

CACHE = "Lcom/android/launcher3/icons/mono/ThemedIconCache;"
DELEGATE = "Lcom/android/launcher3/icons/mono/ThemedIconDelegate;"
p = sys.argv[1]
s = open(p).read()


def once(pattern, text):
    m = list(re.finditer(pattern, text, re.S))
    if len(m) != 1:
        sys.exit(f"STOP: anchor {pattern!r} matched {len(m)} times in {p}")
    return m[0]


# 1. field
m = once(r"\.field public final shapeBounds:Landroid/graphics/Rect;\n", s)
s = s[:m.end()] + f"\n.field private final cache:{CACHE}\n" + s[m.end():]

# 2. constructor: after the first invoke-direct {p0}, Object.<init>; v0 is free there
m = once(r"(\.method public constructor <init>\(Lcom/android/launcher3/icons/mono/ThemedIconInfo;"
         r".*?invoke-direct \{p0\}, Ljava/lang/Object;-><init>\(\)V\n)", s)
s = s[:m.end()] + (f"\n    new-instance v0, {CACHE}\n\n"
                   f"    invoke-direct {{v0}}, {CACHE}-><init>()V\n\n"
                   f"    iput-object v0, p0, {DELEGATE}->cache:{CACHE}\n") + s[m.end():]

# 3. drawContent body
m = once(r"(\.method public drawContent\(Lcom/android/launcher3/icons/BitmapInfo;"
         r"Lcom/android/launcher3/icons/IconShape;Landroid/graphics/Canvas;Landroid/graphics/Rect;"
         r"Landroid/graphics/Paint;\)V\n).*?(\.end method\n)", s)
body = f"""    .registers 14

    iget-object v0, p0, {DELEGATE}->cache:{CACHE}

    move-object v1, p2

    move-object v2, p3

    move-object v3, p4

    move-object v4, p5

    iget-object v5, p0, {DELEGATE}->monoIcon:Landroid/graphics/Bitmap;

    iget-object v6, p0, {DELEGATE}->shapeBounds:Landroid/graphics/Rect;

    iget-object v7, p0, {DELEGATE}->monoPaint:Landroid/graphics/Paint;

    invoke-virtual/range {{v0 .. v7}}, {CACHE}->draw(Lcom/android/launcher3/icons/IconShape;Landroid/graphics/Canvas;Landroid/graphics/Rect;Landroid/graphics/Paint;Landroid/graphics/Bitmap;Landroid/graphics/Rect;Landroid/graphics/Paint;)V

    return-void
"""
s = s[:m.start()] + m.group(1) + body + m.group(2) + s[m.end():]
open(p, "w").write(s)
print("patched", p)
