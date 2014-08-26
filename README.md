# Hubot-Rainforest

[Hubot](http://hubot.github.com/) script to interface with [Rainforest QA](https://www.rainforestqa.com/).

## Installation

Add a dependency to your Hubot instance using NPM:

```bash
$ npm install --save hubot-rainforest
```

Then add this script to the `external-scripts.json`:

```json
["hubot-rainforest"]
```

## Commands

```
> hubot rf subscribe - Subscribe the current channel to test-run status updates
> hubot rf unsubscribe - Remove this room from the subscription list
> hubot rf status - Query the last 5 test runs
> hubot rf subscriptions - List the rooms that are subscribed to status updates
```
