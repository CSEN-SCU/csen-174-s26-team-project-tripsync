# Sprint 1 — CI/CD (Parts 1 and 2)

## Overview

This document covers Sprint 1 CI/CD (Parts 1 and 2). We use GitHub Actions for CI/CD with automatic triggers, and distribute the current build through TestFlight.

## Part 1 — CI pipeline setup

We set up a CI pipeline in GitHub Actions that runs automatically on pushes and pull request updates.

**Merged pull request (Part 1):**  
`https://github.com/CSEN-SCU/csen-174-s26-team-project-tripsync/commit/44c7b6685f294bf76a3bbff2da24e2d27451b66c`

## Part 2 — CD pipeline setup

We set up a CD workflow in GitHub Actions that is automatically triggered and currently live.

### Secrets management

All required secrets are stored in GitHub Secrets and injected at runtime. No credentials are hardcoded or committed.

### Live deployment URL

Our current live deployment/distribution URL is provided through TestFlight:

`[ADD_TESTFLIGHT_LIVE_URL_HERE]`

### Deployment evidence screenshot

Insert a screenshot showing a successful deployment/workflow run from GitHub Actions:

`[ADD_DEPLOYMENT_SCREENSHOT_PATH_OR_EMBED_HERE]`

Example markdown (replace with your actual image path):

`![Successful CI/CD deployment run](../misc-content/REPLACE_WITH_SCREENSHOT_FILENAME.png)`

### Platform paragraph

Our platform is GitHub Actions. It is integrated with our repository, supports automatic push/PR triggers, manages secrets securely, and gives clear visibility into workflow runs.
