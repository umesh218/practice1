#!/bin/bash
PUBLIC_IP=$(terraform output -raw public_ip)
echo "Public IP: $PUBLIC_IP" > public_ip.txt
gh secret set VM_PUBLIC_IP -b "$PUBLIC_IP"
