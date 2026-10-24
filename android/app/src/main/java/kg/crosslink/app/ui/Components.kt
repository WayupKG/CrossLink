package kg.crosslink.app.ui

import android.graphics.Bitmap
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.crosslink.app.R
import kotlin.random.Random

/** A flat card with a hairline border, like replai's inline cards (the shadow is only for floating surfaces). */
@Composable
fun Panel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val t = CrossLinkTheme.tokens
    Column(
        modifier
            .fillMaxWidth()
            .clip(Radius.card)
            .background(t.card)
            .border(1.dp, t.border, Radius.card)
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
        content = content,
    )
}

enum class PillStyle { Primary, Secondary, Outline, Ghost, Inverse, Glass }

/**
 * The only button shape: a pill means "pressable", a rounded rectangle means "type here".
 * Primary is graphite (foreground on background), as in replai; the brand colour marks states.
 */
@Composable
fun Pill(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    style: PillStyle = PillStyle.Primary,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    height: Dp = 48.dp,
    contentColor: Color? = null,
) {
    val t = CrossLinkTheme.tokens
    val compact = height < 44.dp
    val (fill, ink, edge) = when (style) {
        PillStyle.Primary -> Triple(t.foreground, t.background, null)
        PillStyle.Secondary -> Triple(t.muted, t.foreground, null)
        PillStyle.Outline -> Triple(Color.Transparent, t.foreground, t.border)
        PillStyle.Ghost -> Triple(Color.Transparent, t.mutedForeground, null)
        PillStyle.Inverse -> Triple(Color.White, Brand.ink, null)
        PillStyle.Glass -> Triple(Color.White.copy(alpha = 0.10f), Color.White, Color.White.copy(alpha = 0.16f))
    }
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, tween(Motion.quick, easing = Motion.smoothOut), label = "press")
    val alpha by animateFloatAsState(if (enabled) 1f else 0.4f, tween(Motion.fast), label = "enabled")
    Row(
        modifier
            .scale(scale)
            .height(height)
            .clip(CircleShape)
            .background(fill.copy(alpha = fill.alpha * alpha))
            .then(if (edge != null) Modifier.border(1.dp, edge, CircleShape) else Modifier)
            .clickable(source, indication = null, enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = if (compact) 12.dp else 20.dp),
        horizontalArrangement = Arrangement.spacedBy(if (compact) 6.dp else 8.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val color = (contentColor ?: ink).copy(alpha = alpha)
        val label = MaterialTheme.typography.labelLarge
        if (icon != null) Icon(icon, null, Modifier.size(if (compact) 16.dp else 18.dp), tint = color)
        // Three pills in a row on a narrow phone, or a large system font: the label shrinks instead of being cut
        Text(text, style = label, color = color, maxLines = 1,
            autoSize = TextAutoSize.StepBased(minFontSize = 11.sp, maxFontSize = label.fontSize))
    }
}

/** Round icon-only button, 40 dp with a 48 dp-ish touch area from its padding. */
@Composable
fun IconAction(icon: ImageVector, description: String, tint: Color = CrossLinkTheme.tokens.mutedForeground, onClick: () -> Unit) {
    Box(
        Modifier
            .size(40.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClickLabel = description, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, description, Modifier.size(18.dp), tint = tint) }
}

/** Icon on a neutral rounded square (rounded-control), as replai's icon boxes. */
@Composable
fun IconBox(icon: ImageVector, tint: Color = CrossLinkTheme.tokens.foreground, fill: Color = CrossLinkTheme.tokens.muted) {
    Box(Modifier.size(40.dp).clip(Radius.control).background(fill), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(18.dp), tint = tint)
    }
}

@Composable
fun Field(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    minLines: Int = 1,
    maxLines: Int = 6,
) {
    val t = CrossLinkTheme.tokens
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, color = t.mutedForeground) },
        minLines = minLines,
        maxLines = maxLines,
        shape = Radius.control,
        textStyle = MaterialTheme.typography.bodyLarge,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = t.brand,
            unfocusedBorderColor = t.input,
            focusedContainerColor = t.background,
            unfocusedContainerColor = t.background,
            cursorColor = t.brand,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}

/** Thin pill progress bar in the brand colour. */
@Composable
fun ProgressLine(progress: Float, modifier: Modifier = Modifier) {
    val t = CrossLinkTheme.tokens
    val shown by animateFloatAsState(progress, tween(Motion.slow, easing = Motion.smoothOut), label = "progress")
    Box(modifier.fillMaxWidth().height(4.dp).clip(CircleShape).background(t.muted)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(shown.coerceIn(0f, 1f)).clip(CircleShape).background(t.brand))
    }
}

/** Connection dot; a live link breathes with a soft halo. */
@Composable
fun StatusDot(live: Boolean, busy: Boolean, color: Color) {
    val transition = rememberInfiniteTransition(label = "pulse")
    val phase by transition.animateFloat(0f, 1f,
        infiniteRepeatable(tween(1600, easing = Motion.smoothOut), RepeatMode.Restart), label = "phase")
    val dot by animateColorAsState(color, tween(Motion.slow), label = "dot")
    Box(Modifier.size(18.dp), contentAlignment = Alignment.Center) {
        if (live || busy) {
            Box(Modifier.size(8.dp).scale(1f + phase * 1.6f).clip(CircleShape)
                .background(dot.copy(alpha = (1f - phase) * if (live) 0.55f else 0.35f)))
        }
        Box(Modifier.size(8.dp).clip(CircleShape).background(dot))
    }
}

/** The app icon from its adaptive layers, cropped like a launcher does (the 72 of 108 dp safe zone). */
@Composable
fun AppIcon(size: Dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(size * 0.3f)), contentAlignment = Alignment.Center) {
        Image(painterResource(R.mipmap.ic_launcher_background), null, Modifier.requiredSize(size * 1.5f))
        Image(painterResource(R.mipmap.ic_launcher_foreground), null, Modifier.requiredSize(size * 1.5f))
    }
}

/**
 * replai's dark grainy brand surface, lit by the logo's blue and pink glows.
 * [glow] 0..1 brightens the blue light, so a live link visibly "switches on" the panel.
 */
@Composable
fun BrandSurface(glow: Float, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val grain = remember { ShaderBrush(ImageShader(noise(), TileMode.Repeated, TileMode.Repeated)) }
    val t = CrossLinkTheme.tokens
    Box(
        modifier
            .fillMaxWidth()
            .clip(Radius.card)
            .background(Brand.ink)
            .drawBehind {
                val w = size.width
                val h = size.height
                drawRect(Brush.radialGradient(
                    listOf(t.brand.copy(alpha = 0.30f + 0.35f * glow), Color.Transparent),
                    center = Offset(w * 0.92f, -h * 0.05f), radius = w * 0.85f))
                drawRect(Brush.radialGradient(
                    listOf(Brand.pink.copy(alpha = 0.16f + 0.10f * glow), Color.Transparent),
                    center = Offset(w * 0.02f, h * 1.08f), radius = w * 0.7f))
                drawRect(Brush.radialGradient(
                    listOf(Brand.cyan.copy(alpha = 0.10f * glow), Color.Transparent),
                    center = Offset(w * 0.55f, h * 0.55f), radius = w * 0.45f))
                drawRect(grain)
            }
            .border(BorderStroke(1.dp, Color.White.copy(alpha = 0.08f)), Radius.card)
            .padding(22.dp),
    ) {
        CompositionLocalProvider(LocalContentColor provides Color.White) { content() }
    }
}

/** A tile of white specks with random alpha: the film grain of the brand surface. */
private fun noise(): ImageBitmap {
    val side = 160
    val random = Random(7)
    val pixels = IntArray(side * side) { (random.nextInt(0, 26) shl 24) or 0xFFFFFF }
    return Bitmap.createBitmap(pixels, side, side, Bitmap.Config.ARGB_8888).asImageBitmap()
}
