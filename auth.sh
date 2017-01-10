#!/bin/bash

if [ "$1" != "{{ auth_name }}" ]; then
	exit 0
fi
secret={{ secret }}
tmp_file="/tmp/tmp_auth_keys"
last_modified_time=$(stat -c %Y $tmp_file 2> /dev/null || echo 0)
current_time=$(date +%s)
time_since_last_modified=$((current_time - last_modified_time))
if (( time_since_last_modified < 300 )); then
        cat $tmp_file | openssl des3 -d -salt -pass pass:$secret
        exit 0
fi
instance=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | awk -F\" '/region/ {print $4}')
groups=$(aws ec2 describe-instances --region "$region" --instance-id "$instance" --query "Reservations[*].Instances[*].Tags[?Key=='CanSSH'].Value" --output text)
for group in $groups; do
	users=$(aws iam get-group --group-name "$group" --query "Users[*].UserName" --output text)
	if [ $? -gt 0 ]; then
		exit 1
	fi
	for user in $users; do
		ids=$(aws iam list-ssh-public-keys --user-name "$user" --query "SSHPublicKeys[?Status=='Active'].SSHPublicKeyId" --output text)
		for id in $ids; do
			key=$(aws iam get-ssh-public-key --user-name "$user" --ssh-public-key-id "$id" --encoding SSH --query "SSHPublicKey.SSHPublicKeyBody" --output text)
			echo "$key"
		done
	done
done | sort | uniq | tee >(openssl des3 -salt -out $tmp_file -pass pass:$secret)
