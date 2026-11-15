class_name Story
extends RefCounted
## Central story configuration. Change names here and they update everywhere
## (dialogue uses {HERO}, {SISTER}, {HER} tokens).

const HERO_NAME := "Daniel"          # TODO: replace with his real name
const HERO_NICKNAME := "chief"       # what Dad calls him
const SISTER_NAME := "Ada"           # TODO: replace / remove
const GIRLFRIEND_NAME := "Her"       # used from Chapter 3 onward
const BIRTH_DATE_TEXT := "16 November 1987"
const BIRTH_YEAR := 1987

static func fill(text: String) -> String:
	return text.replace("{HERO}", HERO_NAME) \
		.replace("{NICK}", HERO_NICKNAME) \
		.replace("{SISTER}", SISTER_NAME) \
		.replace("{HER}", GIRLFRIEND_NAME)
