# Web of Tomorrow Infrastructure

Creates infrastructure in AWS for the Web of Tomorrow static website. Deploys
the following CloudFormation templates.

- `build-change-set.cfn.yaml`
- `weboftomorrow.cfn.yaml`
- `devops.cfn.yaml`

_It currently depends on another stack that creates many of the root resources._
That root stack is mainly used to setup the shared artifact and static website
buckets as well as many of the roles and other permissions.

---

**[Change log](CHANGELOG.md)**

[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
