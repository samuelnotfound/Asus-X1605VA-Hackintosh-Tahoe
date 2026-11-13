// SSDT-AsusMicLED — Fn+F9 mic LED only (X1605VA)
// samuelnotfound
//
// Prerequisites (BIOS/DSDT renames still required):
//   _Q16 -> XQ16
//
// Compile: iasl SSDT-AsusMicLED.dsl
// Load the resulting AML from OpenCore ACPI.

DefinitionBlock ("", "SSDT", 2, "X1605V", "MicLED", 1)
{
    External (\_SB.PC00.LPCB.EC0, DeviceObj)
    External (\_SB.PC00.LPCB.EC0.XQ16, MethodObj)   // Original F9 query after rename
    External (\_SB.GGOV, MethodObj)                 // Read GPIO
    External (\_SB.SGOV, MethodObj)                 // Write GPIO

    // GPIO 0x09020007 = orange microphone LED on X1605VA

    // Bridge matched by AsusMicLED.kext (IONameMatch ASUSF901)
    Device (F9LR)
    {
        Name (_HID, "ASUSF901")
        Name (_UID, One)

        Method (_STA, 0, NotSerialized)
        {
            If (_OSI ("Darwin")) { Return (0x0F) }
            Return (Zero)
        }

        // Read LED: 0 = off, 1 = on
        Method (GLED, 0, Serialized)
        {
            Return (\_SB.GGOV (0x09020007))
        }

        // Set LED; returns confirmed state or 0xFF on bad arg
        Method (SLED, 1, Serialized)
        {
            If (LGreater (Arg0, One)) { Return (0xFF) }
            \_SB.SGOV (0x09020007, Arg0)
            Return (\_SB.GGOV (0x09020007))
        }
    }

    Scope (\_SB.PC00.LPCB.EC0)
    {
        // Fn+F9 — toggle LED only; micled-agent syncs CoreAudio to LED state
        Method (_Q16, 0, Serialized)
        {
            If (_OSI ("Darwin"))
            {
                If (\_SB.GGOV (0x09020007))
                {
                    \_SB.SGOV (0x09020007, Zero)   // was on → off (unmute)
                }
                Else
                {
                    \_SB.SGOV (0x09020007, One)    // was off → on (mute)
                }
            }
            Else
            {
                XQ16 ()
            }
        }
    }
}
