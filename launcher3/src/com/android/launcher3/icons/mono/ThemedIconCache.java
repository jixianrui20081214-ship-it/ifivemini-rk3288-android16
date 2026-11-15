package com.android.launcher3.icons.mono;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Rect;

import com.android.launcher3.icons.IconNormalizer;
import com.android.launcher3.icons.IconShape;

/**
 * Raster cache for ThemedIconDelegate.drawContent().
 *
 * The stock code clips the icon to the shape path on every draw. On Mali-T, Skia disables GPU
 * path rendering, so each clipPath with a curved shape is rasterised on the CPU and uploaded as
 * a texture, for every themed icon in every frame. This class draws the clipped content once
 * into a bitmap of the destination size and replays it with drawBitmap until any input of that
 * drawing changes.
 *
 * Inputs compared on every draw: the IconShape object, the destination size, the background
 * paint's color, alpha and color filter, and the monochrome paint's alpha and color filter.
 * A rebuild allocates a new bitmap, so a display list recorded with the previous one keeps
 * valid pixels.
 */
final class ThemedIconCache {
    private final Paint mBlit = new Paint(Paint.FILTER_BITMAP_FLAG);
    private Bitmap mBitmap, mMono, mSoftMono;
    private IconShape mShape;
    private int mWidth, mHeight, mColor, mAlpha, mMonoAlpha;
    private ColorFilter mFilter, mMonoFilter;

    void draw(IconShape shape, Canvas canvas, Rect bounds, Paint paint,
            Bitmap mono, Rect shapeBounds, Paint monoPaint) {
        canvas.drawBitmap(shape.shadowLayer, null, bounds, paint);
        int w = bounds.width(), h = bounds.height();
        if (w <= 0 || h <= 0) return;
        if (mBitmap == null || mShape != shape || mWidth != w || mHeight != h
                || mColor != paint.getColor() || mAlpha != paint.getAlpha()
                || mFilter != paint.getColorFilter()
                || mMono != mono || mMonoAlpha != monoPaint.getAlpha() || mMonoFilter != monoPaint.getColorFilter()) {
            Bitmap b = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            Canvas c = new Canvas(b);
            float size = shape.pathSize;
            // the transform GraphicsUtils.resizeToContentSize applies, relative to bounds
            c.scale(w / size, h / size);
            float f = IconNormalizer.ICON_VISIBLE_AREA_FACTOR;
            c.scale(f, f, size / 2, size / 2);
            c.clipPath(shape.path);
            c.drawPaint(paint);
            if (mMono != mono) {
                // A software Canvas cannot draw HARDWARE bitmaps; keep one CPU copy per icon.
                mSoftMono = mono.getConfig() == Bitmap.Config.HARDWARE
                        ? mono.copy(Bitmap.Config.ARGB_8888, false) : mono;
                mMono = mono;
            }
            c.drawBitmap(mSoftMono, null, shapeBounds, monoPaint);
            b.prepareToDraw();
            mBitmap = b;
            mShape = shape;
            mWidth = w;
            mHeight = h;
            mColor = paint.getColor();
            mAlpha = paint.getAlpha();
            mFilter = paint.getColorFilter();
            mMonoAlpha = monoPaint.getAlpha();
            mMonoFilter = monoPaint.getColorFilter();
        }
        canvas.drawBitmap(mBitmap, null, bounds, mBlit);
    }
}
