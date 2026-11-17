// GlassIconTile.kt
//
// The soft 3D frosted-glass icon tile of the Melody glass style: a rounded translucent tile with a
// vertical sky-to-teal tint, a teal inner glow rising from the bottom edge, a small glossy
// highlight near the top-left and a thin light rim. Icons passed in keep their own size and take
// the content colour of the caller (white in the menus and the nav bar).

package com.mochyy.mochymusic.ui.component

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

private val GlassSky = Color(0xFF6ECDFF)
private val GlassTeal = Color(0xFF35D6C0)

@Composable
fun GlassIconTile(
    size: Dp,
    modifier: Modifier = Modifier,
    glow: Float = 0.5f,
    content: @Composable () -> Unit,
) {
    val shape = RoundedCornerShape(size * 0.34f)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(size)
            .clip(shape)
            .drawBehind {
                drawRect(
                    Brush.verticalGradient(
                        listOf(
                            Color.White.copy(alpha = 0.20f),
                            GlassSky.copy(alpha = 0.10f),
                            GlassTeal.copy(alpha = 0.16f),
                        )
                    )
                )
                drawRect(
                    Brush.radialGradient(
                        colors = listOf(GlassTeal.copy(alpha = 0.45f * glow), Color.Transparent),
                        center = Offset(this.size.width * 0.5f, this.size.height),
                        radius = this.size.width * 0.9f,
                    )
                )
                drawCircle(
                    brush = Brush.radialGradient(
                        colors = listOf(Color.White.copy(alpha = 0.30f), Color.Transparent),
                        center = Offset(this.size.width * 0.30f, this.size.height * 0.18f),
                        radius = this.size.width * 0.50f,
                    ),
                    radius = this.size.width * 0.50f,
                    center = Offset(this.size.width * 0.30f, this.size.height * 0.18f),
                )
            }
            .border(
                width = 1.dp,
                brush = Brush.linearGradient(
                    listOf(Color.White.copy(alpha = 0.50f), Color.White.copy(alpha = 0.06f), GlassTeal.copy(alpha = 0.30f))
                ),
                shape = shape,
            ),
    ) {
        // icons larger than the tile interior shrink to fit instead of overflowing the glass
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(size * 0.62f),
        ) {
            content()
        }
    }
}
