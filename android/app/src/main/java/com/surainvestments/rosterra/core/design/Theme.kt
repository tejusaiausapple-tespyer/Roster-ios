package com.surainvestments.rosterra.core.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Mapped from iOS Theme tokens (brand indigo + emerald accent).
val BrandStrong = Color(0xFF4F46E5)
val BrandDeep = Color(0xFF4338CA)
val AccentEmerald = Color(0xFF059669)
val AccentEmeraldDark = Color(0xFF34D399)

private val LightColors = lightColorScheme(
    primary = BrandStrong,
    onPrimary = Color.White,
    secondary = AccentEmerald,
    onSecondary = Color.White,
    tertiary = BrandDeep,
    background = Color(0xFFF7F7FB),
    surface = Color.White,
    onBackground = Color(0xFF111827),
    onSurface = Color(0xFF111827),
    error = Color(0xFFDC2626),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF818CF8),
    onPrimary = Color(0xFF111827),
    secondary = AccentEmeraldDark,
    onSecondary = Color(0xFF111827),
    tertiary = Color(0xFFA5B4FC),
    background = Color(0xFF0B0F19),
    surface = Color(0xFF111827),
    onBackground = Color(0xFFF9FAFB),
    onSurface = Color(0xFFF9FAFB),
    error = Color(0xFFF87171),
)

@Composable
fun RosterraTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
