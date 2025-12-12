import subprocess
from datetime import datetime

def list_models():
    process = subprocess.Popen(['ollama', 'list'], stdout=subprocess.PIPE)
    output, error = process.communicate()
    return [line.split()[0] for line in output.decode('utf-8').strip().split('\n')[1:]]

def pull_model(model):
    subprocess.run(['ollama', 'pull', model])

def check_updates():
    local_models = list_models()
    try:
        remote_models = [line.split()[0] for line in subprocess.check_output(['curl', '-s', 'https://ollama.ai/library']).decode('utf-8').strip().split('\n') if line.strip()]
    except Exception as e:
        print(f"Error checking remote models: {e}")
        return
    updates = set(remote_models) - set(local_models)
    if updates:
        print("Updates available for the following models:", ", ".join(updates))
        with open('ollama_update.log', 'a') as f:
            now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"{now}: Updates installed for models: {', '.join(updates)}\n")
        for model in updates:
            pull_model(model)
    else:
        print("All models are up-to-date.")

check_updates()