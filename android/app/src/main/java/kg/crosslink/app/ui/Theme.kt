package kg.crosslink.app.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kg.crosslink.app.R

/**
 * Design tokens of replai-admin (src/styles/globals.css): white page, graphite text and main
 * buttons, neutral grey fills, thin borders, flat cards, pill buttons, a dark grainy brand surface.
 * The one difference is the brand colour: CrossLink's logo blue instead of replai orange.
 */
@Immutable
class Tokens(
    val background: Color,
    val foreground: Color,
    val card: Color,
    val muted: Color,
    val mutedForeground: Color,
    val border: Color,
    val input: Color,
    /** The logo colour; also the accent for states and focus (--brand / --primary). */
    val brand: Color,
    /** Text on a brand-tinted fill (--primary-strong). */
    val brandStrong: Color,
    val destructive: Color,
    /** Destructive as text on the page: the carmine fill is too dark for text on the dark theme. */
    val destructiveText: Color,
)

private val Light = Tokens(
    background = Color(0xFFFFFFFF),      // 0 0% 100%
    foreground = Color(0xFF1C1A17),      // 30 8% 10%
    card = Color(0xFFFFFFFF),
    muted = Color(0xFFF5F5F5),           // 0 0% 96%
    mutedForeground = Color(0xFF6B6661), // 30 5% 40%
    border = Color(0xFFE3E3E3),          // 0 0% 89%
    input = Color(0xFFD9D9D9),           // 0 0% 85%
    brand = Color(0xFF3552F5),           // 5.7:1 with white text, AA like replai's primary
    brandStrong = Color(0xFF2338B0),
    destructive = Color(0xFF931A2A),     // 352 70% 34%
    destructiveText = Color(0xFF931A2A),
)

private val Dark = Tokens(
    background = Color(0xFF151413),      // 30 5% 8%
    foreground = Color(0xFFECE9E4),      // 40 16% 91%
    card = Color(0xFF201F1D),            // 30 4% 12%
    muted = Color(0xFF2D2B2A),           // 30 4% 17%
    mutedForeground = Color(0xFFB1ACA5), // 35 7% 67%
    border = Color(0xFF2D2B2A),
    input = Color(0xFF2D2B2A),
    brand = Color(0xFF3552F5),
    brandStrong = Color(0xFF9DABFF),
    destructive = Color(0xFF9D2535),     // 352 62% 38%
    destructiveText = Color(0xFFF0919C),
)

/** The brand panel stays the same in both themes, as in replai (--brand-ink is not redefined in .dark). */
object Brand {
    val ink = Color(0xFF1B1A18)          // 30 5% 10%
    val pink = Color(0xFFFF4D8D)         // the second glow of the logo
    val cyan = Color(0xFF22D3EE)
}

/** Radius scale: four steps, then only pills (CircleShape). Buttons are always pills. */
object Radius {
    val field = RoundedCornerShape(8.dp)
    val control = RoundedCornerShape(12.dp)
    val pop = RoundedCornerShape(20.dp)
    val card = RoundedCornerShape(24.dp)
}

/** Motion scale of replai (transitions.dev). Pick by meaning: closing is shorter than opening. */
object Motion {
    const val stagger = 40
    const val quick = 150
    const val fast = 250
    const val medium = 350
    const val slow = 400
    const val verySlow = 500
    val smoothOut = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)
    val bounce = CubicBezierEasing(0.34f, 1.36f, 0.64f, 1f)
    val distanceBase = 8.dp
}

private val Inter = FontFamily(
    Font(R.font.inter_regular, FontWeight.Normal),
    Font(R.font.inter_medium, FontWeight.Medium),
    Font(R.font.inter_semibold, FontWeight.SemiBold),
    Font(R.font.inter_bold, FontWeight.Bold),
)
private val InterDisplay = FontFamily(Font(R.font.inter_display_semibold, FontWeight.SemiBold))

private val AppTypography = Typography(
    headlineMedium = TextStyle(fontFamily = InterDisplay, fontWeight = FontWeight.SemiBold, fontSize = 28.sp,
        lineHeight = 32.sp, letterSpacing = (-0.02).em),
    titleLarge = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold, fontSize = 18.sp,
        lineHeight = 24.sp, letterSpacing = (-0.015).em),
    titleMedium = TextStyle(fontFamily = Inter, fontWeight = FontWeight.SemiBold, fontSize = 15.sp,
        lineHeight = 20.sp, letterSpacing = (-0.01).em),
    bodyLarge = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Normal, fontSize = 13.sp, lineHeight = 18.sp),
    labelLarge = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 15.sp, lineHeight = 20.sp),
    labelMedium = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 16.sp),
    labelSmall = TextStyle(fontFamily = Inter, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp),
)

private val LocalTokens = staticCompositionLocalOf { Light }

object CrossLinkTheme {
    val tokens: Tokens
        @Composable @ReadOnlyComposable get() = LocalTokens.current
}

@Composable
fun CrossLinkTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val t = if (dark) Dark else Light
    // Material components (text fields, selection handles) take their colours from these tokens
    val scheme = (if (dark) darkColorScheme() else lightColorScheme()).copy(
        primary = t.brand, onPrimary = Color.White,
        background = t.background, onBackground = t.foreground,
        surface = t.card, onSurface = t.foreground,
        surfaceVariant = t.muted, onSurfaceVariant = t.mutedForeground,
        outline = t.input, outlineVariant = t.border,
        error = t.destructiveText,
    )
    CompositionLocalProvider(LocalTokens provides t) {
        MaterialTheme(colorScheme = scheme, typography = AppTypography, content = content)
    }
}
