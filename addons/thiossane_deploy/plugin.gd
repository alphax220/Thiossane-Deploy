@tool
extends EditorPlugin
## Thiossane Deploy — Plugin éditeur Godot
## Copyright (c) 2026 Teranga Game Studio. Tous droits réservés.
## Déploiement direct vers la boutique Thiossane Store.

const DOCK_SCRIPT_PATH := "res://addons/thiossane_deploy/thiossane_dock.gd"
const MENU_LABEL := "Thiossane Deploy : show dock / afficher le dock"

var dock: Control


func _enter_tree() -> void:
	# Vérifie que le fichier est bien à la racine addons attendue
	if not FileAccess.file_exists(DOCK_SCRIPT_PATH):
		push_error("[Thiossane Deploy] Fichier manquant : %s" % DOCK_SCRIPT_PATH)
		push_error("Structure attendue : res://addons/thiossane_deploy/{plugin.cfg, plugin.gd, thiossane_dock.gd}")
		return

	var dock_script: GDScript = load(DOCK_SCRIPT_PATH) as GDScript
	if dock_script == null:
		push_error("[Thiossane Deploy] Impossible de charger %s (erreur de syntaxe ?)" % DOCK_SCRIPT_PATH)
		push_error("Ouvrez thiossane_dock.gd dans l'éditeur et regardez l'onglet Erreurs / Débogage.")
		return

	dock = dock_script.new() as Control
	if dock == null:
		push_error("[Thiossane Deploy] Échec d'instanciation du dock (script.new() a renvoyé null)")
		return

	dock.name = "Thiossane Deploy"
	dock.custom_minimum_size = Vector2(320, 400)

	# Dock à droite (à côté de l'Inspecteur)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	add_tool_menu_item(MENU_LABEL, _show_panel)

	print("[Thiossane Deploy] Activé — regardez le dock à DROITE de l'éditeur")
	print("  Onglet « Thiossane Deploy » à côté de Inspecteur / Node")
	print("  Ou : Projet → Outils → %s" % MENU_LABEL)


func _exit_tree() -> void:
	if is_instance_valid(dock):
		remove_control_from_docks(dock)
		dock.queue_free()
	dock = null
	remove_tool_menu_item(MENU_LABEL)


func _show_panel() -> void:
	if not is_instance_valid(dock):
		push_warning("[Thiossane Deploy] Dock invalide — désactivez/réactivez le plugin.")
		return
	remove_control_from_docks(dock)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	# Force la sélection de l'onglet du dock si possible
	print("[Thiossane Deploy] Dock ré-affiché à droite.")


func _get_plugin_name() -> String:
	return "Thiossane Deploy"
