import assert from "node:assert/strict";
import test from "node:test";

import { inputLanguageFromDefaults } from "./input-source.ts";

const defaultsOutput = (name: string) => `
(
    {
        "Bundle ID" = "com.apple.CharacterPaletteIM";
        InputSourceKind = "Non Keyboard Input Method";
    },
    {
        InputSourceKind = "Keyboard Layout";
        "KeyboardLayout Name" = ${name};
    }
)
`;

test("maps ABC to En", () => {
	assert.equal(inputLanguageFromDefaults(defaultsOutput("ABC")), "En");
});

test("maps RussianWin to Ru", () => {
	assert.equal(inputLanguageFromDefaults(defaultsOutput("RussianWin")), "Ru");
});

test("ignores output without a supported keyboard layout", () => {
	assert.equal(inputLanguageFromDefaults(defaultsOutput("British")), undefined);
});
