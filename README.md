# terraform-azure-ai-infra
A collection of enterprise-grade Terraform modules and blueprints for deploying scalable Azure infrastructure, featuring advanced AI patterns like Cosmos DB Vector Search etc., 


# Azure Enterprise Infrastructure Blueprints

This repository contains a growing collection of production-grade Terraform modules and environment configurations for provisioning infrastructure on Microsoft Azure. These blueprints are designed with enterprise best practices, modularity, and strict infrastructure-as-code (IaC) principles to deploy highly scalable, secure, and modern cloud architectures.

## Repository Structure

The architecture of this repository is heavily inspired by the "Environment Monolith" and "Reusable Module" patterns, allowing for clear separation of concerns between infrastructure definition and environment execution.

* `/modules` — Reusable, parameterized Terraform blocks that define specific cloud components (e.g., Cosmos DB Vector Containers, Storage Accounts, AI Services).
* `/services/environments` — Deployable state configurations (e.g., `dev`, `qa`, `prod`) that consume the modules and manage state files and variables for specific application stacks.

## Available Modules

As this repository grows, new infrastructure patterns will be added here.

### 1. Cosmos DB NoSQL Vector Search (`/modules/cosmos_db_container`)
A highly specialized module for provisioning Azure Cosmos DB NoSQL containers with native Vector Search capabilities. 
* **The Problem:** The standard `azurerm` provider does not natively expose vector embedding properties. Furthermore, Cosmos DB vector embedding policies are strictly **immutable** after container creation, meaning standard patch operations will fail silently.
* **The Solution:** This module implements a "One-Resource" pattern utilizing the `azapi` provider. It deploys the entire container, including its throughput, partition keys, excluded indexing paths, and immutable vector policies, via a single atomic `PUT` request to the Azure Resource Manager (ARM) API.

## Prerequisites

Before executing any blueprints in this repository, ensure your local environment is configured with the following:

* [Terraform CLI](https://developer.hashicorp.com/terraform/downloads) (v1.5.0 or newer)
* [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (`az login`)
* Active Azure Subscription with `Contributor` or `Owner` permissions
* *(For Vector Search)* The `EnableNoSQLVectorSearch` capability must be enabled on the target Cosmos DB account.
