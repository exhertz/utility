![Image](https://github.com/user-attachments/assets/11527bc9-fa8b-4b99-9d46-d64096116dff)

# Install SSH pub key

one line:

```bash
curl -sL https://raw.githubusercontent.com/exhertz/utility/main/install_ssh_key.sh | bash -s -- /path/to_public_key.pub
```

or:

```bash
curl -o install_ssh_key.sh https://raw.githubusercontent.com/exhertz/utility/main/install_ssh_key.sh
chmod +x install_ssh_key.sh
./install_ssh_key.sh /path/to/your/public_key.pub
```


# Enable secure SSH params (sshd_config)

one line:

```bash
curl -sL https://raw.githubusercontent.com/exhertz/utility/main/secure_sshd_config.sh | bash
```

or:

```bash
curl -o secure_sshd_config.sh https://raw.githubusercontent.com/exhertz/utility/main/secure_sshd_config.sh
chmod +x secure_sshd_config.sh
./secure_sshd_config.sh
```
