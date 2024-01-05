# aws-secretsmanager.el

`aws-secretsmanager.el` is an Emacs interface for interacting with AWS Secrets Manager. This package allows Emacs users to seamlessly integrate AWS secret management into their workflow.

## Features

- **List Secrets**: Retrieve and display a list of secrets, including their names and ARNs, from AWS Secrets Manager.
- **View Secret Details**: View details of a selected secret in either JSON or plain text format.
- **Toggle Secret Display**: Switch between showing and hiding the values of secrets.
- **Copy Secret Values**: Easily copy secret values to the clipboard for use in other applications.

## Installation

1. Ensure that the AWS CLI is installed and configured on your system.
2. Add the `aws-secretsmanager.el` file to your Emacs load path.
3. Include the following in your Emacs configuration:
   ```emacs-lisp
   (require 'aws-secretsmanager)
   ```

## Usage

### Listing Secrets

To list secrets stored in AWS Secrets Manager, use:

```
M-x aws-secretsmanager-show-secrets-list
```

### Viewing and Interacting with Secrets

- **View Details**: Select a secret from the list and press RET to view its details.
- **Toggle Secret Value Display**: In the details view, press RET on a secret to toggle between showing and hiding its value.
- **Copy Secret Value**: Press w to copy the value of the selected secret.
