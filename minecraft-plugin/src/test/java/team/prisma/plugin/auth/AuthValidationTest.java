package team.prisma.plugin.auth;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

import java.util.UUID;
import java.util.logging.Logger;

import static org.junit.jupiter.api.Assertions.*;

class AuthValidationTest {
    private static final Logger log = Logger.getLogger("test");

    @ParameterizedTest
    @ValueSource(strings = {
        "550e8400-e29b-41d4-a716-446655440000",
        "00000000-0000-0000-0000-000000000000",
        "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
        "abcdefab-cdef-abcd-efab-cdefabcdefab"
    })
    void isValidUuid_валидныеUUID_возвращаетTrue(String uuid) {
        assertTrue(AuthValidation.isValidUuid(uuid), "UUID должен быть валидным: " + uuid);
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "",
        "   ",
        "null",
        "not-a-uuid",
        "550e8400-e29b-41d4-a716",
        "550e8400-e29b-41d4-a716-4466554400000",
        "gggggggg-gggg-gggg-gggg-gggggggggggg",
        "550e8400_e29b_41d4_a716_446655440000"
    })
    void isValidUuid_невалидныеUUID_возвращаетFalse(String uuid) {
        assertFalse(AuthValidation.isValidUuid(uuid), "UUID не должен быть валидным: " + uuid);
    }

    @Test
    void isValidUuid_null_возвращаетFalse() {
        assertFalse(AuthValidation.isValidUuid(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "550e8400-e29b-41d4-a716-446655440000",
        "00000000-0000-0000-0000-000000000000"
    })
    void parseUuidOrNull_валидныеUUID_возвращаетUUID(String uuid) {
        UUID result = AuthValidation.parseUuidOrNull(uuid);
        assertNotNull(result);
        assertEquals(uuid, result.toString());
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "",
        "not-a-uuid",
        "550e8400-e29b-41d4-a716"
    })
    void parseUuidOrNull_невалидныеUUID_возвращаетNull(String uuid) {
        assertNull(AuthValidation.parseUuidOrNull(uuid));
    }

    @Test
    void parseUuidOrNull_null_возвращаетNull() {
        assertNull(AuthValidation.parseUuidOrNull(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "Player",
        "player123",
        "Player_Name",
        "_",
        "a",
        "abcdefghijklmnop"
    })
    void isValidPlayerName_валидныеНики_возвращаетTrue(String name) {
        assertTrue(AuthValidation.isValidPlayerName(name), "Ник должен быть валидным: " + name);
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "",
        "   ",
        "Player Name",
        "player-name",
        "player.name",
        "player@name",
        "abcdefghijklmnopq",
        "Player_Name_Too_Long"
    })
    void isValidPlayerName_невалидныеНики_возвращаетFalse(String name) {
        assertFalse(AuthValidation.isValidPlayerName(name), "Ник не должен быть валидным: " + name);
    }

    @Test
    void isValidPlayerName_null_возвращаетFalse() {
        assertFalse(AuthValidation.isValidPlayerName(null));
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "192.168.1.1",
        "10.0.0.1",
        "255.255.255.255",
        "0.0.0.0",
        "127.0.0.1"
    })
    void isValidIp_валидныеIPv4_возвращаетTrue(String ip) {
        assertTrue(AuthValidation.isValidIp(ip), "IPv4 должен быть валидным: " + ip);
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "2001:0db8:85a3:0000:0000:8a2e:0370:7334",
        "::1",
        "fe80::1ff:fe23:4567:890a"
    })
    void isValidIp_валидныеIPv6_возвращаетTrue(String ip) {
        assertTrue(AuthValidation.isValidIp(ip), "IPv6 должен быть валидным: " + ip);
    }

    @ParameterizedTest
    @ValueSource(strings = {
        "",
        "   ",
        "999.999.999.999",
        "192.168.1",
        "192.168.1.1.1",
        "not-an-ip",
        "2001:db8::1::2"
    })
    void isValidIp_невалидныеIP_возвращаетFalse(String ip) {
        assertFalse(AuthValidation.isValidIp(ip), "IP не должен быть валидным: " + ip);
    }

    @Test
    void isValidIp_null_возвращаетFalse() {
        assertFalse(AuthValidation.isValidIp(null));
    }

    @Test
    void logInvalidInput_неВыбрасываетИсключение() {
        assertDoesNotThrow(() -> AuthValidation.logInvalidInput(log, "test", "field", "value"));
        assertDoesNotThrow(() -> AuthValidation.logInvalidInput(log, "test", "field", null));
        assertDoesNotThrow(() -> AuthValidation.logInvalidInput(log, "test", "field", "a".repeat(100)));
    }
}
