package team.prisma.plugin.auth;

import org.bukkit.entity.Player;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.UUID;
import java.util.logging.Logger;

import static org.mockito.Mockito.*;
import static org.junit.jupiter.api.Assertions.*;

@ExtendWith(MockitoExtension.class)
class MinecraftAuthServiceTest {
    @Mock
    private org.bukkit.plugin.java.JavaPlugin plugin;
    @Mock
    private team.prisma.plugin.http.SupabaseClient supabase;
    @Mock
    private Player player;
    @Mock
    private Logger log;

    private MinecraftAuthService authService;
    private final UUID testUuid = UUID.fromString("550e8400-e29b-41d4-a716-446655440000");

    @BeforeEach
    void setUp() {
        authService = new MinecraftAuthService(plugin, supabase, log);
        when(player.getUniqueId()).thenReturn(testUuid);
        when(player.getName()).thenReturn("TestPlayer");
        when(player.isOnline()).thenReturn(true);
    }

    @Test
    void isAuthenticated_новыйИгрок_возвращаетFalse() {
        assertFalse(authService.isAuthenticated(testUuid));
    }

    @Test
    void markAuthenticated_послеМаркировки_возвращаетTrue() {
        authService.markAuthenticated(testUuid);
        assertTrue(authService.isAuthenticated(testUuid));
    }

    @Test
    void clear_послеОчистки_возвращаетFalse() {
        authService.markAuthenticated(testUuid);
        authService.clear(testUuid);
        assertFalse(authService.isAuthenticated(testUuid));
    }

    @Test
    void validPassword_валидныйПароль_возвращаетTrue() {
        String password = "validPassword123";
        assertTrue(authService.validPassword(password));
    }

    @Test
    void validPassword_короткийПароль_возвращаетFalse() {
        String password = "short";
        assertFalse(authService.validPassword(password));
    }

    @Test
    void validPassword_длинныйПароль_возвращаетFalse() {
        String password = "a".repeat(80);
        assertFalse(authService.validPassword(password));
    }

    @Test
    void validPassword_null_возвращаетFalse() {
        assertFalse(authService.validPassword(null));
    }

    @Test
    void validPassword_пустойПароль_возвращаетFalse() {
        assertFalse(authService.validPassword(""));
        assertFalse(authService.validPassword("   "));
    }

    @Test
    void isAuthenticationCommand_валидныеКоманды_возвращаетTrue() {
        assertTrue(MinecraftAuthService.isAuthenticationCommand("/login password"));
        assertTrue(MinecraftAuthService.isAuthenticationCommand("/register pass pass"));
        assertTrue(MinecraftAuthService.isAuthenticationCommand("/changepass old new"));
        assertTrue(MinecraftAuthService.isAuthenticationCommand("/prismaauth"));
        assertTrue(MinecraftAuthService.isAuthenticationCommand("/auth"));
        assertTrue(MinecraftAuthService.isAuthenticationCommand("login password"));
    }

    @Test
    void isAuthenticationCommand_невалидныеКоманды_возвращаетFalse() {
        assertFalse(MinecraftAuthService.isAuthenticationCommand("/msg hello"));
        assertFalse(MinecraftAuthService.isAuthenticationCommand("/tp player"));
        assertFalse(MinecraftAuthService.isAuthenticationCommand(""));
        assertFalse(MinecraftAuthService.isAuthenticationCommand("   "));
        assertFalse(MinecraftAuthService.isAuthenticationCommand(null));
    }
}
