![Animis Logo](https://github.com/Lonaasan/Animis/blob/main/logo.png)
# Animis Avatar Suite
Multiplayer compatible. Requires OpenStarbound

This mod allows you to animate your characters directives based on the player-state (and bindable loop states!)

## How to Use
Animis can be quite difficult to understand at the beginning, so i will tell you the basics:

For Animis to work, you have to edit and / or add files to it. The most important file for you to edit is:
animis/playerconfig.json

inside of there you currently find a exampleconfig:
```
{
    "1234567890abcdef1234567890abcdef" : {
        "facial_hair" : {
            "enabled": true,
            "idleLoop": false,
            "loungeIdleLoop": false,
            "swimIdleLoop": false,
            "crouchIdleLoop": false,
            "maxFrames": 9,
            "speed": 10,
            "maxRandomValue": 5000,
            "maxRandomTrigger": 1,
            "group": "hair",
            "type": "fem12"
        }
    }
}
```
The long string, `1234567890abcdef1234567890abcdef`, is the player UUID of your character. you can easily get the UUID by copying the name of your player file in your storage/player folder

The UUID holds an object, in this case `facial_hair`, which is one of 5 layers you can animate with Animis. The full list is:

- body
- emote
- hair
- facial_hair
- facial_mask

All of these have different benefits and usecases. For the example, you want to animate `facial_hair`. This is a layer that renders on top of your hair, so it would be perfect for ears or similar usecases!

Inside `facial_hair`, you see different properties. We will go through them one by one.

- `enabled`: tells Animis if the directive should be used or not. Helpful for debug purposes.
- `idleLoop`: if you want your idle animation to loop over multiple directives instead of staying at your choosen personality index, you can set this to `true`
- `loungeIdleLoop`: if you want your lounge idle animation to loop over multiple directives, you can set this to `true`
- `swimIdleLoop`: if you want your swimming idle animation to loop over multiple directives, you can set this to `true`
- `crouchIdleLoop`: if you want your crouch animation to loop over multiple directives, you can set this to `true`
- `maxFrames`: the max number of frames animis will loop through. Mostly just there to stop people from making too many frames. You can also remove this property if you want to use the default in animis/config.json
- `speed`: the speed at which animis goes through your directives. Higher numbers are faster. You can also remove this property if you want to use the default in animis/config.json
- `maxRandomValue`: the maximum value from 1 to x to generate numbers, which the random state will use for its likelyhood. You can also remove this property if you want to use the default in animis/config.json
- `maxRandomTrigger`: the maximum value from 1 to x at which the random state will trigger. You can also remove this property if you want to use the default in animis/config.json
- `group` & `type`: some layers equire a group and type to display properly. You can remove these properties for the `body` and `emote` directives, as they work without them

Now you have set up your playerconfig, but where do you add in the directives for your layers?

For that you have to create a folder named after your player UUID into the animis folder. In our case: `1234567890abcdef1234567890abcdef`.
Into that folder you create json files that are named like the layers we just set up, so lets make `facial_hair.json`.

Our example file has the base structure how such a layerfile can look like:

```
{
    "crouch": [
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "idle": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "jump": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "fall": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "run": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "lounge": [
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "swim": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "swimIdle": [
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "walk": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "switch1": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "switch2": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "loop1": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "loop2": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "once1": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "once2": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "looponce1": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "looponce2": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ],
    "random": [
        "?crop=0;0;1;1?multiply=0000?...",
        "?crop=0;0;1;1?multiply=0000?..."
    ]
}
```

Inside, you see each state with an array of directives.
You can add / remove directives or even delete a state if you dont want it.

### Custom Loops!
As you can see, this file has some states that are not present in vanilla. these are custom loop states! You can set up the binds for them in the mod binds of OpenSB

To add directives, i would recommend using "Air Fryer" from Kae on Discord. You give it an image, and it creates a directive you can paste in, pretty easy!
Link: https://discord.com/oauth2/authorize?client_id=1221620700222197840

After you filled in your desired directives, you are done. Congratulations!

## Installation
Download the latest release or the sourcecode, and paste it into your mods folder for Starbound. Thats everything!
