class_name SkillProfile
extends RefCounted
## Bir oyuncunun becerilerine sorulan TEK arayuz. Sistemler "search_speed"
## gibi etki adlarini sorar; hangi becerinin/dugumun urettigini bilmez.
## Kaynaklar: eski rutbeli beceriler (skills.json, gocle temel degere
## doner) + beceri agaci dugumleri (tree_effects, behaviors).
## `ranks` bos ise ve agac bossa profil NOTR'dur (tum carpanlar 1.0).

var skills: SkillSet
var ranks: Dictionary = {}
var tree_effects: Dictionary = {}     # etki -> toplam (agac)
var behaviors: Dictionary = {}        # davranis kimligi -> true (agac)


func _init(p_skills: SkillSet = null, p_ranks: Dictionary = {}) -> void:
	skills = p_skills
	ranks = p_ranks


func rank(skill_id: String) -> int:
	return int(ranks.get(skill_id, 1))


func bonus(effect: String) -> float:
	var base := 0.0 if skills == null else skills.bonus(effect, ranks)
	return base + float(tree_effects.get(effect, 0.0))


func multiplier(effect: String) -> float:
	return maxf(SkillSet.MIN_MULTIPLIER, 1.0 + bonus(effect))


func has_behavior(id: String) -> bool:
	return behaviors.has(id)


func refresh_tree(nodes: Dictionary) -> void:
	tree_effects = SkillTree.effects_of(nodes)
	behaviors = SkillTree.behaviors_of(nodes)
