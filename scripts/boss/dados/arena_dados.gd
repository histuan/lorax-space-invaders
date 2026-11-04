# Dados da arena da fase 3: tamanho, onde fica e como é desenhada. Os padrões daqui são neutros
# (zero/vazio): os valores de verdade moram no arena.tres.
@tool
class_name ArenaDados
extends Resource

## Largura e altura (px) da arena formada
@export var tamanho := Vector2.ZERO
## Centro horizontal (x do mundo); a arena cresce e encolhe em volta dele
@export var centro_x := 0
## Linha da BASE (y do mundo): fica fixa, a arena cresce para cima
@export var base_y := 0
@export var cor := Color(0, 0, 0, 0)
## Espessura do contorno (px)
@export var espessura := 0
## Lado (px) do ponto de luz em que a arena nasce
@export var ponto_tamanho := 0
## Arte por cima da arena (a árvore em cima); vazia = só o contorno. Ainda não é desenhada
@export var moldura: Texture2D
## A arena nunca passa desta altura (y do mundo) para cima
@export var topo_minimo := 0
