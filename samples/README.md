# Apple Remote Messaging Samples

These files are copyable examples of remote messaging configurations supported by the DuckDuckGo iOS and macOS clients. Each sample uses explicit surfaces because the clients support only specific message type and surface combinations.

## Sample Index

### iOS

- `ios/sample1.json`: the intentionally empty default loaded by iOS and macOS development builds so remote messages do not appear during normal development.
- `ios/sample-new-tab-page.json`: small, medium, single-action, promo, and two-action new-tab messages with different illustrations, a translation, and varied actions.
- `ios/sample-image-url.json`: a new-tab message that demonstrates `imageUrl` with an uploaded `/illustrations` asset and a built-in placeholder fallback.
- `ios/sample-featured-cards-list.json`: a modal cards list with a featured single-action card, remote artwork, and translated CTA.
- `ios/sample-matching-rules.json`: ANDed attributes, alternative matching rules, percentile rollout, and previous-message exclusions.
- `ios/sample-display-conditions.json`: impression-only, days-shown-only, and combined iOS display conditions.
- `ios/sample-survey.json`: basic survey parameters and click-time Search and Duck.ai usage state.
- `ios/sample-cards-list.json`: a modal cards list with remote images, sections, and translations.

### macOS

- `macos/sample-new-tab-page.json`: small, medium, single-action, and two-action new-tab messages with translations and metrics.
- `macos/sample-matching-rules.json`: ANDed attributes, alternative matching rules, percentile rollout, and previous-message exclusions.
- `macos/sample-tab-bar.json`: a survey message displayed in the macOS tab bar.
- `macos/sample-survey.json`: a new-tab survey with click-time Search and Duck.ai usage state.

## Visual Preview Behavior

Except for the dedicated matching-rules samples, the visual samples have empty `matchingRules` and `exclusionRules` arrays, and their top-level `rules` arrays are empty. Point a development build at a sample URL and dismiss the current message to see the next message in that file. Display conditions may also retire a message once its limit is reached.

`ios/sample1.json` is the exception: it must remain empty because iOS and macOS development builds use it as their default configuration.

The display-conditions sample presents its messages in order; dismiss the current message to reach the next scenario. When both conditions are set, the message is auto-dismissed when either limit is reached first. The combined example uses 3 impressions and 7 days so the impression limit can be exercised within one day. The days-shown limit starts from the message's first display, not the app's install date.

## Matching and Exclusion Rules

The matching-rules samples use the same three examples on both platforms: multiple attributes within one rule, alternative matching rules, and a 100% percentile rollout with multiple exclusions. The matching paths use minimum versions of `0.0.0`, and the interaction exclusions reference fictitious earlier campaigns, so all three messages remain easy to preview on a fresh development profile. Replace those permissive values when adapting the examples for a real campaign.

Within `matchingRules`, rule IDs are alternatives: the message is eligible when any referenced rule matches. Within one rule, every attribute must match. Within `exclusionRules`, the message is rejected when any referenced rule matches.

## Supported Combinations

| Platform | Message types | Surfaces |
| --- | --- | --- |
| iOS | `small`, `medium`, `big_single_action`, `big_two_action`, `promo_single_action` | `new_tab_page` |
| iOS | `cards_list` | `modal` |
| macOS | `small`, `medium`, `big_single_action`, `big_two_action` | `new_tab_page` |
| macOS | `big_single_action` with a `survey` primary action | `tab_bar` |

The schemas contain the shared surface names, but a schema-valid message can still be discarded if its message type is not supported on the declared surface. Always declare `surfaces` in new configurations.

## Survey Parameters

The `additionalParameters.queryParams` value is a semicolon-separated list. The Apple clients support these exact values:

- `ddgv`: app version
- `atb`: ATB
- `var`: ATB variant
- `delta`: days installed
- `mo`: hardware model
- `last_duck_ai_usage`: Duck.ai usage state
- `last_search_state`: Search usage state
- `locale`: locale
- `osv`: operating system version
- `ppro_status`: subscription status
- `ppro_platform`: subscription purchase platform
- `ppro_billing`: subscription billing period
- `ppro_tier`: subscription tier
- `ppro_days_since_purchase`: days since subscription purchase
- `ppro_days_until_exp`: days until subscription expiry or renewal
- `ppro_trial_active`: whether a subscription trial is active
- `vpn_first_used`: days since VPN was first used
- `vpn_last_used`: days since VPN was last used

If any requested parameter is unknown, the clients discard the survey action. The new-tab survey examples use `last_search_state` and `last_duck_ai_usage` because those values are refreshed immediately before the survey opens. The macOS tab-bar example uses only parameters captured while the configuration is processed.

## Validate Locally

Install Node.js, then run from the repository root:

```sh
for file in samples/ios/*.json; do
  npx --yes ajv-cli@5.0.0 validate -s schemas/ios/schema.json -d "$file" --all-errors
done

for file in samples/macos/*.json; do
  npx --yes ajv-cli@5.0.0 validate -s schemas/macos/schema.json -d "$file" --all-errors
done
```
