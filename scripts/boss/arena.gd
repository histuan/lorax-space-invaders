# A arena da fase 3: o retângulo onde a nave fica presa. Desenhada por código, em pixels inteiros,
# sempre com a BASE (base_y) e o centro_x fixos: cresce e encolhe para cima. Nasce como um ponto
# de luz que vira linha e a linha vira caixa. Tudo em tempo real (pausa com o Pause).
class_name Arena
extends Node2D

# O retângulo jogável mudou (a nave presa nele deve acompanhar)
signal retangulo_mudou(retangulo: Rect2)

@export var dados: ArenaDados

# Tamanho desenhado agora (no meio de uma animação é o parcial)
var atual := Vector2.ZERO
# Tamanho para onde a arena vai (o de quando a animação acabar)
var alvo := Vector2.ZERO
var tween: Tween = null

# Começa apagada, já no tamanho dos dados
func _ready():
	visible = false
	alvo = dados.tamanho
	atual = alvo

# Ponto ou linha (sem miolo) sai cheio; a caixa, só o contorno
func _draw():
	var r = retangulo()
	if r.size.y <= 2 * dados.espessura:
		draw_rect(r, dados.cor)
	else:
		draw_rect(r.grow(-dados.espessura / 2.0), dados.cor, false, dados.espessura)

# O retângulo jogável desenhado agora
func retangulo() -> Rect2:
	return retangulo_de(atual)

# O retângulo de quando a animação em curso acabar (nascer ou mudar_tamanho)
func retangulo_final() -> Rect2:
	return retangulo_de(alvo)

# Um tamanho virado retângulo de pixels inteiros, de pé na base, centrado no centro_x
func retangulo_de(tamanho: Vector2) -> Rect2:
	var largura = roundi(tamanho.x)
	var altura = roundi(tamanho.y)
	return Rect2(dados.centro_x - floori(largura / 2.0), dados.base_y - altura, largura, altura)

# Ponto de luz no centro da base → linha horizontal (ponto_linha s) → caixa (linha_caixa s)
func nascer(ponto_linha: float, linha_caixa: float):
	modulate.a = 1.0
	visible = true
	definir_atual(Vector2(dados.ponto_tamanho, dados.ponto_tamanho))
	var linha = Vector2(alvo.x, dados.espessura)
	var t = novo_tween()
	t.tween_method(definir_atual, atual, linha, ponto_linha)
	t.tween_method(definir_atual, linha, alvo, linha_caixa)
	t.tween_callback(avisar)

# Cresce ou encolhe até 'novo' em 'tempo' s (0 = na hora), sem passar do topo_minimo; avisa a cada passo
func mudar_tamanho(novo: Vector2, tempo: float):
	var altura_max = dados.base_y - dados.topo_minimo
	if novo.y > altura_max:
		push_warning("Arena: altura %d passa do topo_minimo; ficou %d" % [novo.y, altura_max])
		novo.y = altura_max
	alvo = novo
	if tempo <= 0.0:
		parar_tween()
		definir_e_avisar(novo)
		return
	novo_tween().tween_method(definir_e_avisar, atual, novo, tempo)

# Apaga a arena: na hora (tempo 0) ou com fade
func sumir(tempo := 0.0):
	parar_tween()
	if tempo <= 0.0:
		visible = false
		return
	var t = novo_tween()
	t.tween_property(self, "modulate:a", 0.0, tempo)
	t.tween_callback(hide)

# Aparece já formada no tamanho alvo, sem animação
func aparecer():
	parar_tween()
	modulate.a = 1.0
	visible = true
	definir_e_avisar(alvo)

# Volta ao tamanho dos dados, formada e apagada (o R do LAB)
func restaurar():
	parar_tween()
	alvo = dados.tamanho
	definir_atual(alvo)
	modulate.a = 1.0
	visible = false

# Troca o tamanho desenhado
func definir_atual(tamanho: Vector2):
	atual = tamanho
	queue_redraw()

# Troca o tamanho desenhado e avisa quem está preso nela
func definir_e_avisar(tamanho: Vector2):
	definir_atual(tamanho)
	avisar()

# Emite retangulo_mudou com o retângulo de agora
func avisar():
	retangulo_mudou.emit(retangulo())

# Um tween novo em tempo real (o anterior é cortado)
func novo_tween() -> Tween:
	parar_tween()
	tween = create_tween().set_ignore_time_scale(true)
	return tween

# Corta a animação em curso
func parar_tween():
	if tween != null:
		tween.kill()
		tween = null
