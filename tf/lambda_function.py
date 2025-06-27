import json
import boto3
import os
import time

REGION = os.environ.get("REGION", "us-west-1")

ec2 = boto3.client("ec2", region_name=REGION)
ssm = boto3.client("ssm", region_name=REGION)
autoscaling = boto3.client("autoscaling", region_name=REGION)

def lambda_handler(event, context):
    print("📩 Event received:", json.dumps(event))

    for record in event.get("Records", []):
        sns_message = record.get("Sns", {}).get("Message")
        if not sns_message:
            print("⚠️ No SNS message found.")
            continue

        message = json.loads(sns_message)

        # 🔒 Skip test notification
        if message.get("Event") == "autoscaling:TEST_NOTIFICATION":
            print("⚠️ Ignoring test notification.")
            continue

        instance_id = message['EC2InstanceId']
        hook_name = message['LifecycleHookName']
        asg_name = message['AutoScalingGroupName']

        print(f"🚀 Handling instance: {instance_id} from ASG: {asg_name}")

        # Step 1: Find control plane instance
        cp_instance_id = find_control_plane()
        print(f"🔐 Found control plane instance: {cp_instance_id}")

        # Step 2: Run kubeadm on control plane
        command_id = run_join_command_on_cp(cp_instance_id)
        time.sleep(8)

        # Step 3: Get output of the join command
        join_cmd = get_ssm_output(cp_instance_id, command_id)
        print(f"🔧 Join command: {join_cmd}")

        # Step 4: Send join command to worker
        run_join_command_on_worker(instance_id, join_cmd)
        print(f"✅ Sent join command to worker: {instance_id}")

        # Step 5: Complete lifecycle hook
        complete_lifecycle(hook_name, asg_name, instance_id)
        print(f"✅ Lifecycle completed for {instance_id}")

    return {"status": "success"}


def find_control_plane():
    filters = [
        {"Name": "tag:Role", "Values": ["control-panel"]},
        {"Name": "instance-state-name", "Values": ["running"]}
    ]
    reservations = ec2.describe_instances(Filters=filters)["Reservations"]
    return reservations[0]["Instances"][0]["InstanceId"]


def run_join_command_on_cp(instance_id):
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": ["kubeadm token create --print-join-command"]},
    )
    return response["Command"]["CommandId"]


def get_ssm_output(instance_id, command_id):
    response = ssm.get_command_invocation(
        InstanceId=instance_id,
        CommandId=command_id
    )
    return response["StandardOutputContent"].strip()


def run_join_command_on_worker(instance_id, command):
    ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": [command]},
    )


def complete_lifecycle(hook_name, asg_name, instance_id):
    autoscaling.complete_lifecycle_action(
        LifecycleHookName=hook_name,
        AutoScalingGroupName=asg_name,
        LifecycleActionResult="CONTINUE",
        InstanceId=instance_id
    )
