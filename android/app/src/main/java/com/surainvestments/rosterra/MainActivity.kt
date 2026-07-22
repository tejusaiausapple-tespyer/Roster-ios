package com.surainvestments.rosterra

import com.surainvestments.rosterra.core.design.Mod
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import com.surainvestments.rosterra.core.design.RosterraTheme
import com.surainvestments.rosterra.ui.navigation.RosterraRoot
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            RosterraTheme {
                Surface(modifier = Mod.fillMaxSize()) {
                    RosterraRoot()
                }
            }
        }
    }
}
