// X1605VA Assistant - samuelnotfound (https://github.com/samuelnotfound)
// Source for SSDT-X1605VA-Assistant.aml. Compile with iasl; OpenCore loads the AML.
// A backslash starts at the ACPI namespace root. Braces delimit a block.
// Zero, One and Ones are the ASL constants 0, 1 and all bits set.
// A Method lists its name, argument count and whether concurrent calls are serialized.
// Existing BIOS 305 DSDT renames must remain enabled:
// KBLU -> XBLU, _Q0E -> XQ0E, _Q0F -> XQ0F, _Q16 -> XQ16, _Q18 -> XQ18.
// Load this in place of the four split tables. No startup method or GPIO write is added.

// Emit an SSDT with AML revision 2, OEM ID X1605V, table ID X1605VAH, OEM revision 1.
DefinitionBlock ("", "SSDT", 2, "X1605V", "X1605VAH", 1)
{
    // External declares a firmware object without redefining it.
    External (\_SB.ATKD, DeviceObj)                     // ASUS hotkey device.
    External (\_SB.ATKD.IANE, MethodObj)                // Dispatches one ASUS hotkey event code.
    External (\_SB.PC00.LPCB.EC0, DeviceObj)            // Embedded controller hosting EC queries.
    External (\_SB.PC00.LPCB.EC0.GLKB, MethodObj)        // Reads backlight support or level, selected by its argument.
    External (\_SB.PC00.LPCB.EC0.ST9E, MethodObj)        // Firmware write used by the keyboard PWM path.
    External (\_SB.PC00.LPCB.EC0.XBLU, MethodObj)        // Original keyboard backlight cycle after rename.
    External (\_SB.PC00.LPCB.EC0.XQ0E, MethodObj)        // Original brightness-down query after rename.
    External (\_SB.PC00.LPCB.EC0.XQ0F, MethodObj)        // Original brightness-up query after rename.
    External (\_SB.PC00.LPCB.EC0.XQ16, MethodObj)        // Original F9 query after rename.
    External (\_SB.PC00.LPCB.EC0.XQ18, MethodObj)        // Original MyASUS query after rename.
    External (\_SB.PC00.LPCB.PS2K, DeviceObj)           // Keyboard device receiving synthetic key notices.
    External (\_SB.GGOV, MethodObj)                    // Reads a GPIO output.
    External (\_SB.SGOV, MethodObj)                    // Sets a GPIO output.

    // Keyboard backlight and screen brightness.



    Device (BKOS)  // Advertise the percentage backlight interface.
    {
        Name (_HID, "ASUSB402")  // Hardware ID for the percentage backlight marker.
        Method (_STA, 0, NotSerialized)  // Expose this device only under macOS.
        {
            If (_OSI ("Darwin")) { Return (0x0F) }  // Report present, enabled, visible and functioning on macOS.
            Return (Zero)  // Report this device as absent on other operating systems.
        }
    }

    Scope (\_SB.PC00.LPCB.EC0)  // Add these objects under the existing embedded controller.
    {
        Name (KBPC, Ones)  // Start the cached percentage with an invalid value so the first read seeds it.
        Mutex (KBMX, 0)  // Protect the percentage cache and PWM write with a mutex at sync level 0.
        Method (GKPC, 0, NotSerialized)  // Read the cached keyboard backlight percentage.
        {
            If (LNot (GLKB (One))) { Return (0xFF) }  // Return the failure sentinel if backlight support is absent.
            If (Acquire (KBMX, 100)) { Return (0xFF) }  // Wait up to 100 ms for the lock and fail on timeout.
            If (LGreater (KBPC, 100))  // Seed the cache if it contains an invalid percentage.
            {
                KBPC = Divide (((GLKB (0x02) * 100) + One), 0x03)  // Convert the firmware level 0-3 to the rounded percentage.
                If (LGreater (KBPC, 100)) { KBPC = Zero }  // Fall back to 0% if the converted firmware value is out of range.
            }
            Local0 = KBPC  // Copy the cached result before unlocking.
            Release (KBMX)  // Release the cache lock before returning.
            Return (Local0)  // Return the result saved in Local0.
        }
        Method (SKPC, 1, NotSerialized)  // Set the keyboard backlight percentage.
        {
            If (LGreater (Arg0, 100)) { Return (0xFF) }  // Reject requests above 100%.
            If (LNot (GLKB (One))) { Return (0xFF) }  // Return the failure sentinel if backlight support is absent.
            If (Acquire (KBMX, 100)) { Return (0xFF) }  // Wait up to 100 ms for the lock and fail on timeout.

            Local0 = Divide (((Arg0 * 0xFF) + 50), 100)  // Scale 0-100% to the nearest 8-bit PWM value.
            If (ST9E (0x1F, 0xFF, Local0))  // Use firmware's backlight PWM write and check its failure result.
            {
                Release (KBMX)  // Release the cache lock before returning.
                Return (0xFF)  // Report failure with the out-of-range sentinel 255.
            }
            KBPC = Arg0  // Cache the requested percent after the firmware write succeeds.
            Local0 = KBPC  // Copy the cached result before unlocking.
            Release (KBMX)  // Release the cache lock before returning.
            Return (Local0)  // Return the result saved in Local0.
        }
        Method (KBLU, 0, Serialized)  // Handle the physical backlight-cycle key.
        {
            If (_OSI ("Darwin"))  // Use the replacement path on macOS.
            {
                If (GLKB (One))  // Continue only if the firmware reports backlight support.
                {
                    Local0 = GKPC ()  // Read the current brightness in percent.
                    If (LLessEqual (Local0, 100))  // Proceed only with a valid percentage.
                    {

                        If (LLess (Local0, 33)) { Local0 = 33 }  // Advance to 33%.
                        ElseIf (LLess (Local0, 67)) { Local0 = 67 }  // Otherwise advance to 67%.
                        ElseIf (LLess (Local0, 100)) { Local0 = 100 }  // Otherwise advance to 100%.
                        Else { Local0 = Zero }  // Wrap 100% back to off.
                        If (LLessEqual (SKPC (Local0), 100))  // Apply the preset and send the event only on success.
                        {
                            Notify (\_SB.PC00.LPCB.PS2K, 0x0368)  // Send the F17 backlight-change notice.
                        }
                    }
                }
            }
            Else { XBLU () }  // Use the original keyboard backlight method on other operating systems.
        }

        Method (_Q0E, 0, NotSerialized)  // Handle the EC brightness-down key query.
        {
            If (_OSI ("Darwin"))  // Use the replacement path on macOS.
            {
                \_SB.ATKD.IANE (0x20)  // Dispatch the existing ASUS brightness-down event.
            }
            Else  // Use the original firmware handler on other operating systems.
            {
                XQ0E ()  // Call the original brightness-down query.
            }

            Return (Zero)  // Finish the EC query with its existing zero return value.
        }

        Method (_Q0F, 0, NotSerialized)  // Handle the EC brightness-up key query.
        {
            If (_OSI ("Darwin"))  // Use the replacement path on macOS.
            {
                \_SB.ATKD.IANE (0x10)  // Dispatch the existing ASUS brightness-up event.
            }
            Else  // Use the original firmware handler on other operating systems.
            {
                XQ0F ()  // Call the original brightness-up query.
            }

            Return (Zero)  // Finish the EC query with its existing zero return value.
        }
    }

    Scope (\_SB.ATKD)  // Add the backlight callback under the existing ASUS hotkey device.
    {
        Method (SKBV, 1, Serialized)  // Accept the legacy 8-bit backlight request.
        {
            If (_OSI ("Darwin"))  // Use the replacement path on macOS.
            {
                If (\_SB.PC00.LPCB.EC0.GLKB (One))  // Check firmware backlight support.
                {
                    Local0 = Arg0  // Copy the requested raw brightness value for clamping.
                    If ((Local0 > 0xFF))  // Check whether the raw brightness exceeds the 8-bit maximum.
                    {
                        Local0 = 0xFF  // Clamp the raw value to 255.
                    }

                    Local1 = Divide (((Local0 * 100) + 127), 0xFF)  // Convert the 8-bit value to the nearest integer percentage.
                    \_SB.PC00.LPCB.EC0.SKPC (Local1)  // Send the converted value to the percentage setter.
                    Return (Local0)  // Return the result saved in Local0.
                }
            }

            Return (Zero)  // Report zero for an unsupported request.
        }
    }

    // F9 microphone LED and key events.
    Scope (\_SB.PC00.LPCB.EC0)  // Add these objects under the existing embedded controller.
    {
        Method (_Q16, 0, Serialized)  // Handle the F9 EC query.
        {
            If (_OSI ("Darwin"))  // Use the replacement path on macOS.
            {

                If (\_SB.GGOV (0x09020007))  // Read the board-specific microphone LED GPIO and branch if lit.
                {
                    \_SB.SGOV (0x09020007, Zero)  // Turn the orange LED off.

                    Notify (\_SB.PC00.LPCB.PS2K, 0x0369)  // Send F18 so the helper requests microphone unmute.
                }
                Else  // Handle the opposite LED state.
                {
                    \_SB.SGOV (0x09020007, One)  // Turn the orange LED on.

                    Notify (\_SB.PC00.LPCB.PS2K, 0x036A)  // Send F19 so the helper requests microphone mute.
                }
            }
            Else  // Handle the opposite LED state.
            {
                XQ16 ()  // Call the original F9 query on other operating systems.
            }
        }
    }

    // Command bridge for microphone LED, trackpad and backlight.
    Device (F9LR)  // Expose the Assistant driver command endpoint.
    {
        Name (_HID, "ASUSF901")  // Hardware ID matched by the Assistant driver.
        Name (_UID, One)  // Give this endpoint instance ID 1.
        Method (_STA, 0, NotSerialized)  // Expose this device only under macOS.
        {
            If (_OSI ("Darwin")) { Return (0x0F) }  // Report present, enabled, visible and functioning on macOS.
            Return (Zero)  // Report this device as absent on other operating systems.
        }
        Method (GLED, 0, Serialized)  // Read the orange LED output.
        {
            Return (\_SB.GGOV (0x09020007))  // Return the current LED GPIO output.
        }
        Method (SLED, 1, Serialized)  // Set the orange LED output and read it back.
        {
            If (LGreater (Arg0, One)) { Return (0xFF) }  // Reject any LED request other than 0 or 1.
            \_SB.SGOV (0x09020007, Arg0)  // Write the requested LED output value.
            Return (\_SB.GGOV (0x09020007))  // Return the current LED GPIO output.
        }


        Method (TTPD, 0, Serialized)  // Request a trackpad toggle; the app checks the resulting state.
        {
            If (_OSI ("Darwin"))  // Use the replacement path on macOS.
            {
                If (CondRefOf (\_SB.ATKD.IANE))  // Verify the ASUS notification method exists before calling it.
                {
                    \_SB.ATKD.IANE (0x6B)  // Queue the existing ASUS trackpad toggle event.
                    Return (Zero)  // Report that the event was queued.
                }
            }
            Return (0xFF)  // Report failure with the out-of-range sentinel 255.
        }
        Method (GBKL, 0, Serialized)  // Expose the backlight read to the driver.
        {
            Return (\_SB.PC00.LPCB.EC0.GKPC ())  // Forward the percentage read to the EC method.
        }
        Method (SBKL, 1, Serialized)  // Expose the backlight write to the driver.
        {
            If (LGreater (Arg0, 100)) { Return (0xFF) }  // Reject requests above 100%.
            Return (\_SB.PC00.LPCB.EC0.SKPC (Arg0))  // Forward the percentage write and return its result.
        }
    }

    // Fn+F12 MyASUS key.
    Device (FNHK)  // Advertise the MyASUS key event to the app.
    {
        Name (_HID, "ASUSF121")  // Hardware ID for the Fn+F12 marker.
        Method (_STA, 0, NotSerialized)  // Expose this device only under macOS.
        {
            If (_OSI ("Darwin")) { Return (0x0F) }  // Report present, enabled, visible and functioning on macOS.
            Return (Zero)  // Report this device as absent on other operating systems.
        }
    }
    Scope (\_SB.PC00.LPCB.EC0)  // Add these objects under the existing embedded controller.
    {
        Method (_Q18, 0, NotSerialized)  // Handle the MyASUS key EC query.
        {
            If (_OSI ("Darwin"))  // Use the replacement path on macOS.
            {
                Notify (\_SB.PC00.LPCB.PS2K, 0x0367)  // Send F16 so the helper toggles its menu.
            }
            Else { XQ18 () }  // Use the original MyASUS query on other operating systems.
            Return (Zero)  // Finish the EC query with its existing zero return value.
        }
    }
}
