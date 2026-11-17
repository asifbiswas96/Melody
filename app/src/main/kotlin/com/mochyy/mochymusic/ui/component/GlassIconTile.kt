// GlassIconTile.kt
//
// The soft 3D frosted-glass icon of the Melody glass style, built from the tile recipe in the
// approved MoreFrame reel source (its `.ic` class): a 36%-radius tile with a 165 degree body from
// the accent to a dark accent, a soft accent highlight at the top-left, a strong accent glow
// rising from the bottom edge, a white inner top highlight, a thin white rim, an accent drop
// glow, a small glossy corner arc at the bottom-right and a white glyph with a soft glow and a
// dark contact shadow. Each icon takes its own accent from the palette.

package com.mochyy.mochymusic.ui.component

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

val GemSky = Color(0xFF6ECDFF)
val GemTeal = Color(0xFF35D6C0)
val GemViolet = Color(0xFFB07CFF)
val GemBlue = Color(0xFF2F8BFF)
private val GemOcean = Color(0xFF27A0E6)
private val GemPalette = listOf(GemBlue, GemViolet, GemTeal, GemOcean)
private var gemCounter = 0

private fun DrawScope.drawGem(c: Color, glow: Float) {
    val w = this.size.width
    val h = this.size.height
    // body: 165 degree from the accent to a dark accent
    drawRect(
        Brush.linearGradient(
            colors = listOf(c.copy(alpha = 0.70f), lerp(Color(0xFF05060A), c, 0.22f)),
            start = Offset(w * 0.28f, 0f),
            end = Offset(w * 0.72f, h),
        )
    )
    // soft accent highlight, top-left
    drawRect(
        Brush.radialGradient(
            colors = listOf(c.copy(alpha = 0.55f), Color.Transparent),
            center = Offset(w * 0.30f, h * 0.22f),
            radius = w * 0.62f,
        )
    )
    // accent glow rising from the bottom edge
    drawRect(
        Brush.verticalGradient(
            0.62f to Color.Transparent,
            1f to c.copy(alpha = (0.75f * (0.5f + glow)).coerceAtMost(0.9f)),
        )
    )
    // white inner highlight along the top
    drawRect(
        Brush.verticalGradient(
            0f to Color.White.copy(alpha = 0.22f),
            0.16f to Color.Transparent,
        )
    )
    // glow behind the glyph
    drawCircle(
        Brush.radialGradient(
            colors = listOf(Color.White.copy(alpha = 0.22f), Color.Transparent),
            center = Offset(w * 0.5f, h * 0.5f),
            radius = w * 0.38f,
        ),
        radius = w * 0.38f,
        center = Offset(w * 0.5f, h * 0.5f),
    )
    // inset edge glow: the frosted rim of the approved tile (accent light collects at the edges, centre calmer)
    drawRect(
        Brush.radialGradient(
            0.50f to Color.Transparent,
            1f to c.copy(alpha = 0.42f),
            center = Offset(w * 0.5f, h * 0.5f),
            radius = w * 0.74f,
        )
    )
    // the glossy corner arc, bottom-right: hugs the corner, soft grey-white, small so it never crosses the glyph
    val r = w * 0.15f
    drawArc(
        color = Color.White.copy(alpha = 0.50f),
        startAngle = 5f,
        sweepAngle = 80f,
        useCenter = false,
        topLeft = Offset(w * 0.74f - r, h * 0.74f - r),
        size = Size(r * 2f, r * 2f),
        style = Stroke(width = w * 0.035f, cap = StrokeCap.Round),
    )
}

/** The 3D glass body, usable behind any control: round buttons, pills and tiles. */
fun Modifier.glassGem(shape: Shape, tint: Color = GemBlue, glow: Float = 0.6f): Modifier =
    this
        .clip(shape)
        .drawBehind { drawGem(tint, glow) }
        .border(
            width = 1.5.dp,
            brush = Brush.linearGradient(
                listOf(Color.White.copy(alpha = 0.34f), Color.White.copy(alpha = 0.12f), tint.copy(alpha = 0.45f))
            ),
            shape = shape,
        )

@Composable
fun GlassIconTile(
    size: Dp,
    modifier: Modifier = Modifier,
    glow: Float = 0.5f,
    tint: Color? = null,
    content: @Composable () -> Unit,
) {
    val accent = tint ?: remember { GemPalette[(gemCounter++) % GemPalette.size] }
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(size)
            // the accent drop glow under the tile
            .drawBehind {
                drawCircle(
                    Brush.radialGradient(
                        colors = listOf(accent.copy(alpha = 0.32f), Color.Transparent),
                        center = Offset(this.size.width * 0.5f, this.size.height * 0.68f),
                        radius = this.size.width * 0.78f,
                    ),
                    radius = this.size.width * 0.78f,
                    center = Offset(this.size.width * 0.5f, this.size.height * 0.68f),
                )
            }
            .glassGem(RoundedCornerShape(size * 0.36f), accent, glow),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(size * 0.62f),
        ) {
            // contact shadow: the glyph again, flattened to near black and pushed down
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(size * 0.62f)
                    .offset(y = size * 0.03f)
                    .graphicsLayer {
                        compositingStrategy = CompositingStrategy.Offscreen
                        alpha = 0.40f
                    }
                    .drawWithContent {
                        drawContent()
                        drawRect(Color(0xFF020A1C), blendMode = BlendMode.SrcIn)
                    },
            ) { content() }
            // the glyph itself: solid white
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(size * 0.62f)
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(Color.White, blendMode = BlendMode.SrcIn)
                    },
            ) { content() }
        }
    }
}

/** The big translucent glass card of the player: sheen from the top-left, teal light rising at the right, lit rim. */
fun Modifier.glassCard(shape: Shape, tint: Color = GemSky): Modifier =
    this
        .clip(shape)
        .drawBehind {
            val w = this.size.width
            val h = this.size.height
            drawRect(
                Brush.verticalGradient(
                    listOf(Color(0xFF1A2A4D).copy(alpha = 0.55f), Color(0xFF0B1226).copy(alpha = 0.62f))
                )
            )
            drawRect(
                Brush.radialGradient(
                    colors = listOf(tint.copy(alpha = 0.30f), Color.Transparent),
                    center = Offset(w * 0.12f, 0f),
                    radius = w * 0.75f,
                )
            )
            drawRect(
                Brush.radialGradient(
                    colors = listOf(GemTeal.copy(alpha = 0.32f), Color.Transparent),
                    center = Offset(w * 0.88f, h),
                    radius = w * 0.60f,
                )
            )
            drawRect(
                Brush.verticalGradient(
                    0f to Color.White.copy(alpha = 0.16f),
                    0.40f to Color.Transparent,
                )
            )
        }
        .border(
            width = 1.dp,
            brush = Brush.linearGradient(
                listOf(Color.White.copy(alpha = 0.55f), Color.White.copy(alpha = 0.06f), tint.copy(alpha = 0.40f))
            ),
            shape = shape,
        )
