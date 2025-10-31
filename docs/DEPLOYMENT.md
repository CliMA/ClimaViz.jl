# Documentation Deployment Guide

This guide explains how to set up automatic documentation deployment to GitHub Pages.

## Prerequisites

Your repository needs a `DOCUMENTER_KEY` secret for deploying to GitHub Pages.

## Setup Steps

### 1. Generate SSH Deploy Key

Run this in Julia REPL:

```julia
using DocumenterTools

# Generate the SSH key pair
DocumenterTools.genkeys(user="CliMA", repo="ClimaViz.jl")
```

This will:
- Generate a public/private SSH key pair
- Display the public key (to add to GitHub as a deploy key)
- Display the private key (to add as a repository secret)

### 2. Add Deploy Key to GitHub

1. Go to your repository settings: `https://github.com/CliMA/ClimaViz.jl/settings/keys`
2. Click "Add deploy key"
3. Title: "Documenter"
4. Key: Paste the **public key** from step 1
5. Check "Allow write access"
6. Click "Add key"

### 3. Add Secret to GitHub

1. Go to repository secrets: `https://github.com/CliMA/ClimaViz.jl/settings/secrets/actions`
2. Click "New repository secret"
3. Name: `DOCUMENTER_KEY`
4. Value: Paste the **private key** from step 1 (the entire multi-line key)
5. Click "Add secret"

### 4. Merge the PR and Wait for First Deployment

1. Merge your pull request to the `main` branch
2. The GitHub Actions workflow will run automatically
3. On the first successful run, Documenter.jl will create the `gh-pages` branch
4. Wait for the action to complete (check the "Actions" tab)

### 5. Enable GitHub Pages (After First Deployment)

**Note**: You must complete step 4 first, as the `gh-pages` branch won't exist until the first deployment.

1. Go to repository settings: `https://github.com/CliMA/ClimaViz.jl/settings/pages`
2. Under "Source", select "Deploy from a branch"
3. Select branch: `gh-pages` and folder: `/ (root)`
4. Click "Save"

## How It Works

The GitHub Actions workflow (`.github/workflows/documentation.yml`) will:

1. **On push to `main`**: Build and deploy documentation to the `gh-pages` branch
2. **On pull requests**: Build documentation to check for errors (but don't deploy)
3. **On tags**: Build and deploy versioned documentation

## Viewing Documentation

Once deployed, your documentation will be available at:
- **Latest (dev)**: `https://clima.github.io/ClimaViz.jl/dev/`
- **Stable**: `https://clima.github.io/ClimaViz.jl/stable/` (after tagging a release)

## Local Testing

To build documentation locally:

```bash
julia --project=docs docs/make.jl
```

The built documentation will be in `docs/build/`.

## Troubleshooting

### Deployment fails with authentication error
- Verify that `DOCUMENTER_KEY` secret is properly set
- Regenerate the key pair if needed

### Documentation not updating
- Check the Actions tab for build errors
- Ensure GitHub Pages is enabled and set to deploy from `gh-pages` branch

### Build succeeds but deployment skipped
- This is expected for pull requests
- Only pushes to `main` and tags will deploy
