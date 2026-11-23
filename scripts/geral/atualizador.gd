# Procura versão nova nas Releases do GitHub; se o jogador aceitar, troca o .exe e reabre o jogo.
# Só age no jogo exportado para Windows (no editor e nos outros alvos não faz nada).
extends CanvasLayer

signal abriu
signal fechou

const API = "https://api.github.com/repos/histuan/lorax-space-invaders/releases/latest"
# Nome EXATO do .exe anexado à Release (sem espaços: o GitHub troca espaço por ponto).
# O publicar.ps1 exporta com este mesmo nome; o exe local do jogador pode ter qualquer nome.
const NOME_ASSET = "lorax-deforestationders.exe"
const DOWNLOAD_OFICIAL = "https://github.com/"
const CABECALHOS = ["User-Agent: lorax-deforestationders-updater", "Accept: application/vnd.github+json"]
# Só em build de debug: --atualizador-teste=http://127.0.0.1:PORTA/arquivo.json troca a API por um servidor local
const ARG_TESTE = "--atualizador-teste="
const PREFIXO_TESTE = "http://127.0.0.1:"
# Só junto com a URL de teste: aceita a pergunta sozinho (testes sem clique)
const ARG_ACEITAR = "--atualizador-aceitar"
# O publicar.ps1 confere o exe novo: grava a versão neste arquivo e sai (arquivo, pois o exe release não tem stdout)
const ARG_GRAVAR_VERSAO = "--gravar-versao="
const REGEX_VERSAO = "^v?\\d+\\.\\d+\\.\\d+$"
# Download sem bytes novos por este tempo = desiste (não há limite de tempo total: internet lenta termina)
const PARADO_MAX = 30.0
const FONTE = preload("res://fonts/atari-classic-font/AtariClassic-gry3.ttf")

# Uma checagem por execução: voltar ao menu não pergunta de novo
static var ja_checou = false

# O pai liga/desliga: a pergunta só aparece com a tela inicial livre (sem menu, seletor ou jogo começando)
var pode_perguntar = false
var exe = ""
var http: HTTPRequest
var asset = {}
var pendente = false
var baixando = false
var bytes_vistos = -1
var visto_em = 0
var raiz: Control
var texto: Label
var botao_sim: Button
var botao_nao: Button

# Limpa sobras da troca anterior e, uma vez por execução, pergunta ao GitHub a última versão
func _ready():
	if not OS.has_feature("windows") or OS.has_feature("editor"):
		return
	layer = 9
	exe = OS.get_executable_path()
	_apagar_sobras()
	if ja_checou:
		return
	ja_checou = true
	http = HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	http.request_completed.connect(_on_versao_recebida)
	if http.request(_url_api(), CABECALHOS) != OK:
		http.queue_free()

# Mostra a pergunta quando houver; durante o download, atualiza a porcentagem
func _process(_delta):
	if pendente and pode_perguntar:
		pendente = false
		_mostrar()
		if _url_teste() != "" and ARG_ACEITAR in OS.get_cmdline_args() + OS.get_cmdline_user_args():
			_baixar()
	if baixando:
		var bytes = http.get_downloaded_bytes()
		var agora = Time.get_ticks_msec()
		if bytes != bytes_vistos:
			bytes_vistos = bytes
			visto_em = agora
		elif agora - visto_em > PARADO_MAX * 1000:
			baixando = false
			_falhar("DOWNLOAD PARADO.")
			return
		texto.text = "BAIXANDO... %d%%" % (100 * bytes / int(asset.size))

# Esc com a pergunta aberta = AGORA NÃO (durante o download e a conferência não fecha)
func _input(event):
	if raiz and raiz.visible and botao_nao.visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		_fechar()

# Compara versões X.Y.Z por partes inteiras (0.10.0 > 0.9.0); qualquer outro formato = false
static func versao_maior(nova: String, atual: String) -> bool:
	var regex = RegEx.create_from_string(REGEX_VERSAO)
	if not regex.search(nova) or not regex.search(atual):
		return false
	var a = nova.trim_prefix("v").split(".")
	var b = atual.trim_prefix("v").split(".")
	for i in 3:
		if a[i].to_int() != b[i].to_int():
			return a[i].to_int() > b[i].to_int()
	return false

# Caminho pedido em --gravar-versao=; vazio = execução normal
static func arquivo_gravar_versao() -> String:
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg.begins_with(ARG_GRAVAR_VERSAO):
			return arg.trim_prefix(ARG_GRAVAR_VERSAO)
	return ""

# Se foi pedido, grava a versão no arquivo, fecha o jogo e devolve true
static func gravar_versao_pedida(arvore: SceneTree) -> bool:
	var caminho = arquivo_gravar_versao()
	if caminho == "":
		return false
	var arquivo = FileAccess.open(caminho, FileAccess.WRITE)
	var gravou = arquivo != null and arquivo.store_string(str(ProjectSettings.get_setting("application/config/version", "")))
	arquivo = null # fecha antes de sair
	arvore.quit(0 if gravou else 1)
	return true

# Apaga o .old (exe antigo) e o .novo (download pela metade); falhou = tenta na próxima abertura
func _apagar_sobras():
	for sufixo in [".old", ".novo"]:
		if FileAccess.file_exists(exe + sufixo):
			DirAccess.remove_absolute(exe + sufixo)

# URL da API; no debug, aceita o servidor local de teste (nunca outro host)
func _url_api() -> String:
	var url = _url_teste()
	return url if url != "" else API

# Lê o argumento de teste, só em build de debug e só para 127.0.0.1
func _url_teste() -> String:
	if not OS.is_debug_build():
		return ""
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		var url = arg.trim_prefix(ARG_TESTE)
		if arg.begins_with(ARG_TESTE) and url.begins_with(PREFIXO_TESTE) and not "@" in url:
			return url
	return ""

# Resposta da API: qualquer coisa estranha = ignora em silêncio
func _on_versao_recebida(result, codigo, _cabecalhos, corpo):
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or codigo != 200:
		return
	var json = JSON.new() # o parse_string escreveria erro no log; aqui a falha é silenciosa
	if json.parse(corpo.get_string_from_utf8()) != OK:
		return
	var dados = json.data
	if not dados is Dictionary or not dados.get("assets") is Array:
		return
	var tag = str(dados.get("tag_name", "")).trim_prefix("v")
	if not versao_maior(tag, str(ProjectSettings.get_setting("application/config/version", "0.0.0"))):
		return
	var origem = PREFIXO_TESTE if _url_teste() != "" else DOWNLOAD_OFICIAL
	for a in dados.assets:
		if a is Dictionary and a.get("name") == NOME_ASSET and str(a.get("browser_download_url", "")).begins_with(origem) and int(a.get("size", 0)) > 0:
			asset = a
			asset.tag = tag
			pendente = true
			return

# Monta e abre a caixa da pergunta
func _mostrar():
	_montar()
	texto.text = "NOVA VERSÃO %s DISPONÍVEL. ATUALIZAR AGORA?" % asset.tag
	botao_sim.grab_focus()
	abriu.emit()

# Cria a caixa por código: fundo escuro, texto e os dois botões
func _montar():
	raiz = Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.theme = Theme.new()
	raiz.theme.default_font = FONTE
	raiz.theme.default_font_size = 8
	add_child(raiz)
	var fundo = ColorRect.new()
	fundo.color = Color(0, 0, 0, 0.85)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(fundo)
	var caixa = VBoxContainer.new()
	caixa.set_anchors_preset(Control.PRESET_FULL_RECT)
	caixa.offset_left = 16
	caixa.offset_right = -16
	caixa.alignment = BoxContainer.ALIGNMENT_CENTER
	caixa.add_theme_constant_override("separation", 12)
	raiz.add_child(caixa)
	texto = Label.new()
	texto.autowrap_mode = TextServer.AUTOWRAP_WORD
	texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caixa.add_child(texto)
	var linha = HBoxContainer.new()
	linha.alignment = BoxContainer.ALIGNMENT_CENTER
	linha.add_theme_constant_override("separation", 12)
	caixa.add_child(linha)
	botao_sim = Button.new()
	botao_sim.text = "ATUALIZAR"
	botao_sim.pressed.connect(_baixar)
	linha.add_child(botao_sim)
	botao_nao = Button.new()
	botao_nao.text = "AGORA NÃO"
	botao_nao.pressed.connect(_fechar)
	linha.add_child(botao_nao)

# AGORA NÃO / OK: esconde a caixa e devolve a tela inicial
func _fechar():
	raiz.visible = false
	fechou.emit()

# ATUALIZAR: baixa o .exe ao lado do atual como .novo (o HTTPRequest segue os redirects do GitHub)
func _baixar():
	botao_sim.visible = false
	botao_nao.visible = false
	http = HTTPRequest.new()
	http.download_file = exe + ".novo"
	http.timeout = 0.0 # o timeout do HTTPRequest é tempo TOTAL; quem desiste é o _process (PARADO_MAX)
	http.download_chunk_size = 1048576 # o padrão (64 KB por quadro) limita o download a ~4 MB/s
	add_child(http)
	http.request_completed.connect(_on_baixou)
	if http.request(asset.browser_download_url, CABECALHOS) != OK:
		_falhar("NÃO CONSEGUI BAIXAR.")
		return
	bytes_vistos = -1
	visto_em = Time.get_ticks_msec()
	baixando = true

# Download terminou: confere, troca os arquivos sem nunca ficar sem exe, abre o novo e sai
func _on_baixou(result, codigo, _cabecalhos, _corpo):
	baixando = false
	var novo = exe + ".novo"
	var velho = exe + ".old"
	if result != HTTPRequest.RESULT_SUCCESS or codigo != 200:
		_falhar("ERRO NO DOWNLOAD (%d/%d)." % [result, codigo])
		return
	var arquivo = FileAccess.open(novo, FileAccess.READ)
	var tamanho = arquivo.get_length() if arquivo else -1
	arquivo = null # fecha antes do rename
	if tamanho != int(asset.size):
		_falhar("ARQUIVO INCOMPLETO.")
		return
	var digest = str(asset.get("digest", ""))
	if digest.begins_with("sha256:"):
		texto.text = "CONFERINDO..."
		await get_tree().process_frame # o sha256 trava o quadro: o texto precisa aparecer antes
		if FileAccess.get_sha256(novo) != digest.trim_prefix("sha256:"):
			_falhar("ARQUIVO CORROMPIDO.")
			return
	if not trocar_arquivos(exe):
		_falhar("NÃO CONSEGUI TROCAR O JOGO.")
		return
	if OS.create_process(exe, []) == -1:
		DirAccess.rename_absolute(exe, novo)
		DirAccess.rename_absolute(velho, exe)
		_falhar("NÃO CONSEGUI ABRIR A VERSÃO NOVA.")
		return
	get_tree().quit()

# Põe o .novo no lugar do exe guardando o atual como .old; falhou no meio = desfaz (nunca fica sem exe)
static func trocar_arquivos(caminho: String) -> bool:
	var velho = caminho + ".old"
	DirAccess.remove_absolute(velho)
	if DirAccess.rename_absolute(caminho, velho) != OK:
		return false
	if DirAccess.rename_absolute(caminho + ".novo", caminho) != OK:
		DirAccess.rename_absolute(velho, caminho)
		return false
	return true

# Qualquer falha: apaga o download, avisa e deixa só o OK (o jogo atual segue funcionando)
func _falhar(motivo: String):
	if http:
		http.cancel_request()
	DirAccess.remove_absolute(exe + ".novo")
	texto.text = motivo + " O JOGO CONTINUA NESTA VERSÃO."
	botao_nao.text = "OK"
	botao_nao.visible = true
	botao_nao.grab_focus()
