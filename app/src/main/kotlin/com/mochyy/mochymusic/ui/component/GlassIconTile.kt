// GlassIconTile.kt
//
// The soft 3D frosted-glass icon of the Melody glass style. The tile is a puffy translucent gem:
// a diagonal tint body, a colour glow rising from the bottom edge, a darker lower lip for depth,
// a soft specular dome plus a small glossy dot top-left and a lit rim. The glyph inside is not a
// flat white shape: it is drawn as a raised piece with a dark extruded shadow under it and a
// white-to-tint face, so every icon reads as a small 3D object on the glass.

package com.mochyy.mochymusic.ui.component

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

val GemSky = Color(0xFF6ECDFF)
val GemTeal = Color(0xFF35D6C0)
val GemViolet = Color(0xFF9A8CFF)

/** The 3D glass body, usable behind any control: round buttons, pills and tiles. */
fun Modifier.glassGem(shape: Shape, tint: Color = GemSky, glow: Float = 0.6f): Modifier =
    this
        .clip(shape)
        .drawBehind {
            val w = this.size.width
            val h = this.size.height
            drawRect(
                Brush.linearGradient(
                    colors = listOf(tint.copy(alpha = 0.50f), Color(0xFF0E1A38).copy(alpha = 0.80f)),
                    start = Offset(0f, 0f),
                    end = Offset(w, h),
                )
            )
            drawRect(
                Brush.radialGradient(
                    colors = listOf(tint.copy(alpha = 0.60f * glow), Color.Transparent),
                    center = Offset(w * 0.5f, h * 1.02f),
                    radius = w * 0.85f,
                )
            )
            drawRect(
                Brush.verticalGradient(
                    0.60f to Color.Transparent,
                    1f to Color.Black.copy(alpha = 0.30f),
                )
            )
            drawOval(
                brush = Brush.radialGradient(
                    colors = listOf(Color.White.copy(alpha = 0.55f), Color.Transparent),
                    center = Offset(w * 0.34f, h * 0.20f),
                    radius = w * 0.40f,
                ),
                topLeft = Offset(w * 0.08f, h * 0.04f),
                size = Size(w * 0.62f, h * 0.36f),
            )
            drawCircle(
                color = Color.White.copy(alpha = 0.85f),
                radius = w * 0.035f,
                center = Offset(w * 0.22f, h * 0.20f),
            )
        }
        .border(
            width = 1.dp,
            brush = Brush.linearGradient(
                listOf(Color.White.copy(alpha = 0.70f), Color.White.copy(alpha = 0.08f), tint.copy(alpha = 0.50f))
            ),
            shape = shape,
        )

@Composable
fun GlassIconTile(
    size: Dp,
    modifier: Modifier = Modifier,
    glow: Float = 0.5f,
    tint: Color = GemSky,
    content: @Composable () -> Unit,
) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(size)
            .glassGem(RoundedCornerShape(size * 0.34f), tint, glow),
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(size * 0.62f),
        ) {
            // the extruded edge: the glyph again, flattened to a dark tint and pushed down
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(size * 0.62f)
                    .offset(y = size * 0.04f)
                    .graphicsLayer {
                        compositingStrategy = CompositingStrategy.Offscreen
                        alpha = 0.65f
                    }
                    .drawWithContent {
                        drawContent()
                        drawRect(Color(0xFF020A1C), blendMode = BlendMode.SrcIn)
                    },
            ) { content() }
            // the raised face: white at the top fading into the tint at the bottom
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(size * 0.62f)
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(
                            Brush.verticalGradient(listOf(Color.White, Color.White, tint.copy(alpha = 0.85f))),
                            blendMode = BlendMode.SrcIn,
                        )
                    },
            ) { content() }
        }
    }
}
