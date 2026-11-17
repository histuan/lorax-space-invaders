# Tela inicial: animações do título, splash, Lorax e trúfulas; Enter começa o jogo.
extends Node2D

@onready var titulo = $CanvasLayer/VBoxContainer/LabelTitulo

const MAIN = preload("res://cenas/geral/main.tscn")

# Frases do splash (uma é sorteada cada vez que a tela abre)
const FRASES = [
	"AGORA COM MOTOSSERRA!",
	"100% ORGANICO",
	"NENHUMA ARVORE FOI MACHUCADA",
	"SERA A A QUE EU SOU RUIM...",
	"FEITO COM ARVORES REAIS",
	"I HAVE NO MOUTH AND I MUST TALK!"
]

@onready var label_enter = $CanvasLayer/VBoxContainer/LabelEnter
@onready var splash = $CanvasLayer/Splash
@onready var lorax = $CanvasLayer/sprites/Lorax
@onready var flash = $CanvasLayer/Flash

# tempo: relógio das animações · saindo: trava a tela após o Enter · base_y: altura original de cada trúfula
var tempo = 0.0
var saindo = false
var escala_lorax: Vector2
var base_y = {}

const DetectorCodigo = preload("res://scripts/geral/detector_codigo.gd")
const SeletorEtapa = preload("res://scripts/geral/seletor_etapa.gd")
const PAUSE_MENU = preload("res://cenas/geral/pause_menu.tscn")
const ATUALIZADOR = preload("res://scripts/geral/atualizador.gd")
const FONTE = preload("res://fonts/atari-classic-font/AtariClassic-gry3.ttf")
# Número da versão (valores TESTE): a barra de controles ocupa o rodapé (y 238), então fica logo acima dela
const VERSAO_TAMANHO = 8
const VERSAO_COR = Color(0.012, 0.012, 0.012, 0.882)
const VERSAO_MARGEM = 2
const VERSAO_TOPO_BARRA = 238

var detector
var seletor
# Com o seletor aberto, o Enter é dele e não inicia o jogo normal
var seletor_aberto = false
# Menu de Esc/P (o PauseMenu no modo menu principal): com ele aberto, o Enter é dos botões
var menu
var menu_aberto = false
# Quadro em que o menu fechou: o Enter que aperta o VOLTAR não pode iniciar o jogo no mesmo quadro
var quadro_fechou = -10
# Pergunta de versão nova (só no exe do Windows): com ela aberta, o Enter e as setas são dela
var atualizador
var atualizador_aberto = false

# Guarda os valores originais para animar a partir deles
func _ready():
	Partida.limpar_etapa()
	criar_menu()
	criar_cheat()
	criar_atualizador()
	criar_versao()
	escala_lorax = lorax.scale
	splash.text = FRASES.pick_random()
	for s in $CanvasLayer/sprites.get_children():
		if s != lorax:
			base_y[s] = round(s.position.y)

# Anima tudo com senos do tempo
func _process(delta):
	tempo += delta
	atualizador.pode_perguntar = not saindo and not seletor_aberto and not menu_aberto
	if saindo:
		return

	# PRESS ENTER pisca (modulate e não visible, para o VBox não reorganizar o título)
	label_enter.modulate.a = 1.0 if fmod(tempo, 1.0) < 0.6 else 0.0
	# Título pulsa e balança em torno do centro
	titulo.pivot_offset = titulo.size / 2
	var escala_titulo = 1.0 + 0.1 * sin(tempo * 3.0)
	titulo.scale = Vector2(escala_titulo, escala_titulo)
	titulo.rotation = deg_to_rad(4.0 * sin(tempo * 1.7))

	# Splash pulsa rápido
	var pulso = 1.0 + 0.08 * sin(tempo * 8.0)
	splash.pivot_offset = splash.size / 2
	splash.scale = Vector2(pulso, pulso)

	# Lorax "respira"
	lorax.scale = escala_lorax * (1.0 + 0.03 * sin(tempo * 4.0))

	# Trúfulas balançam, cada uma defasada
	var i = 0
	for s in base_y:
		s.position.y = base_y[s] + round(sin(tempo * 2.0 + i) * 1.5)
		i += 1

	var enter_livre = not seletor_aberto and not menu_aberto and not atualizador_aberto and Engine.get_process_frames() - quadro_fechou > 1
	if Input.is_action_just_pressed("ui_accept") and enter_livre:
		comecar()

# Cria o menu de Esc/P antes do cheat (o seletor fica depois na árvore e recebe o Esc primeiro)
func criar_menu():
	menu = PAUSE_MENU.instantiate()
	menu.modo_menu_principal = true
	add_child(menu)
	menu.abriu.connect(_on_menu_abriu)
	menu.fechou.connect(_on_menu_fechou)

# Menu aberto: as setas são dele (Konami desligado)
func _on_menu_abriu():
	menu_aberto = true
	detector.ativo = false

# Menu fechado: volta o Konami e guarda o quadro para a trava do Enter
func _on_menu_fechou():
	menu_aberto = false
	quadro_fechou = Engine.get_process_frames()
	detector.ativo = true

# Mostra "v" + a versão do project.godot no canto de baixo, à esquerda
func criar_versao():
	var label = Label.new()
	label.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	label.add_theme_font_override("font", FONTE)
	label.add_theme_font_size_override("font_size", VERSAO_TAMANHO)
	label.add_theme_color_override("font_color", VERSAO_COR)
	$CanvasLayer/controles.add_sibling(label)
	label.reset_size()
	label.position = Vector2(VERSAO_MARGEM, VERSAO_TOPO_BARRA - VERSAO_MARGEM - label.size.y)

# Cria o detector do código Konami e o seletor de etapa e liga os sinais
func criar_cheat():
	detector = DetectorCodigo.new()
	seletor = SeletorEtapa.new()
	add_child(detector)
	add_child(seletor)
	detector.codigo_digitado.connect(_abrir_seletor)
	seletor.etapa_escolhida.connect(_on_etapa_escolhida)
	seletor.cancelado.connect(_fechar_seletor)

# Cria o atualizador (ele mesmo decide se age) e liga a pergunta à trava do Enter
func criar_atualizador():
	atualizador = ATUALIZADOR.new()
	add_child(atualizador)
	atualizador.abriu.connect(_on_atualizador_abriu)
	atualizador.fechou.connect(_on_atualizador_fechou)

# Pergunta aberta: Konami e menu de Esc desligados
func _on_atualizador_abriu():
	atualizador_aberto = true
	detector.ativo = false
	menu.pode_abrir = false

# Pergunta fechada: volta tudo e guarda o quadro para a trava do Enter
func _on_atualizador_fechou():
	atualizador_aberto = false
	quadro_fechou = Engine.get_process_frames()
	detector.ativo = true
	menu.pode_abrir = true

# Código certo: abre a lista com as etapas de Partida.NOMES_ETAPAS
func _abrir_seletor():
	if saindo or seletor_aberto or menu_aberto or atualizador_aberto:
		return
	var opcoes = []
	for etapa in Partida.NOMES_ETAPAS:
		opcoes.append({"nome": Partida.NOMES_ETAPAS[etapa], "etapa": etapa})
	seletor_aberto = true
	detector.ativo = false
	menu.pode_abrir = false
	Sons.tocar(&"cheat_abre")
	seletor.abrir(opcoes)

# Esc no seletor: volta à tela inicial normal
func _fechar_seletor():
	seletor_aberto = false
	detector.ativo = true
	menu.pode_abrir = true

# Etapa escolhida: grava na Partida e começa o jogo com a transição de sempre
func _on_etapa_escolhida(etapa):
	Partida.escolher_etapa(etapa)
	comecar()

# Som de start (continua tocando na troca de cena), zoom no Lorax, flash,
# música abaixa e, no fim, troca para o jogo
func comecar():
	saindo = true
	menu.pode_abrir = false
	$CanvasLayer/controles.set_process(false)
	label_enter.modulate.a = 1.0
	var t = create_tween().set_parallel()
	var som = $sons/start
	som.reparent(get_tree().root)
	som.play()
	som.finished.connect(som.queue_free)
	t.tween_property(lorax, "scale", escala_lorax * 1.4, 0.15)
	t.tween_property(flash, "color:a", 1.0, 0.6)
	t.tween_property($sons/musga, "volume_db", -40.0, 0.6)
	t.chain().tween_callback(func(): get_tree().change_scene_to_packed(MAIN))
