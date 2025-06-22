import os
import shutil

SOKOL_PATH = "source/lib/sokol"

def unpatch_sokol():
	"""Remove Android patches from Sokol bindings"""
	print("Removing Android patches from Sokol bindings...")
	
	# Just restore from backup
	for root, _, files in os.walk(SOKOL_PATH):
		for file in files:
			if file.endswith(".android_backup"):
				backup_path = os.path.join(root, file)
				original_path = backup_path.removesuffix(".android_backup")
				
				# Restore from backup
				shutil.move(backup_path, original_path)
				print(f"Restored {original_path}")

if __name__ == "__main__":
    unpatch_sokol() 