# BASES TEORICAS DEL SIMULADOR EMS
## Electric Malfunction Simulation
### Documento tecnico de fundamento fisico-matematico y arquitectura del software

---

## 0. RESUMEN EJECUTIVO

**Nombre del proyecto:** EMS (Electric Malfunction Simulation)
**Motor:** Godot Engine 4.6 (renderer Mobile, Jolt Physics 2D, autoload `Globals`)
**Lenguaje:** GDScript 4.x
**Version del documento:** 1.0
**Audiencia objetivo:** Estudiantes de electrotecnia, tecnicos electricistas, aficionados a la simulacion y desarrolladores que deseen extender el proyecto.

### Proposito
EMS es un simulador pedagogico de redes electricas residenciales en baja tension. Modela el comportamiento de cables, fuentes de alimentacion, paneles de distribucion, breakers termomagneticos, reguladores de voltaje y cargas (electrodomesticos) en regimen cuasi-estacionario, con un fuerte enfasis en la retroalimentacion visual (color y vibracion) para que el usuario "sienta" los fenomenos electricos en tiempo real.

### Que SI simula
- Ley de Ohm y potencia electrica.
- Caida de tension en cables por resistencia serie.
- Estres termico de cables (relacion I/I_max).
- Maquina de estados de los consumidores: OFF, UNDERVOLTAGE, NORMAL, OVERVOLTAGE, BROKEN.
- Protecciones termomagneticas IEC 60898 (curvas B, C, D y disparo termico I^2t).
- Regulacion de voltaje (AVR) con clipping y blackout.
- Distribucion split-phase 220V a 2 x 110V con corriente de neutro.
- Inrush de cargas (corrientes de arranque segun clase de dispositivo).

### Que NO simula (declarado explicitamente)
- Reactancias inductivas/capacitivas (modelo DC puro).
- Efecto skin ni coeficiente de temperatura del cobre.
- Potencia compleja/instantanea (P = V*I, coseno phi como fudge).
- Integracion termica real del cable (sigma = I/I_max instantaneo).
- Sistemas trifasicos.
- Proteccion diferencial (GFCI/RCD).
- Persistencia del estado BROKEN (requiere recarga de escena).

---

## 1. INTRODUCCION Y PROPOSITO

### 1.1 Que es un EMS educativo
Un Electrical Management System (EMS) educativo es una herramienta software que permite experimentar con una red electrica simplificada sin riesgo fisico y sin la complejidad de un simulador profesional (SPICE, ETAP, OpenDSS). El objetivo no es reemplazar a estas herramientas, sino construir intuicion sobre fenomenos que en la realidad son invisibles: la cada de tension en un cable largo, el disparo de un breaker frente a una sobrecarga sostenida, el parpadeo de una lampara bajo subtension, etc.

EMS se posiciona en el nicho de los "serious games" de electrotecnia. Sacrifica precision cuantitativa a cambio de:
- **Respuesta inmediata** (un solo frame para recalcular la red completa).
- **Visualizacion dramatica** del estado fisico (colores, temblores, luces que parpadean).
- **Transparencia del modelo** (un panel "H" muestra exactamente que se aproxima y que se ignora).

### 1.2 Objetivos de aprendizaje
Tras interactuar con el simulador, el usuario deberia poder:
1. Predecir cualitativamente el efecto de aumentar o reducir el voltaje de red.
2. Identificar por que un cable se "pone rojo" y empieza a temblar.
3. Entender la diferencia entre disparo magnetico (cortocircuito) y disparo termico (sobrecarga sostenida).
4. Comprender la funcion de un regulador de voltaje (AVR) y de un breaker.
5. Reconocer los sintomas visuales del bajo voltaje (amarillento) y la sobretension (naranja + vibracion).

### 1.3 Stack tecnologico
- **Godot 4.6 Mobile renderer** (forward+, sin SDFGI). El proyecto es 2D puro.
- **GDScript** como unico lenguaje. No hay shaders personalizados.
- **Jolt Physics 2D** (configurado en `project.godot:28`) aunque el simulador no realiza consultas fisicas; queda como configuracion por defecto.
- **Autoload `Globals`** (`globals.gd`, `uid://bct7ul2r20dc0`): unico singleton. Expone la senal `global_voltage_changed(voltage)` y la variable `current_day_factor` (factor dia/noche en [0, 1]).
- **Escena principal:** `scenes/main_engine.tscn` (uid `dfao1nv5mrsqd`).
- **Renderer:** `d3d12` en Windows, configurado en `project.godot:32`.

---

## 2. MARCO TEORICO DE CIRCUITOS ELECTRICOS

### 2.1 Ley de Ohm
La ley fundamental que rige todo el simulador:

    V = I * R    (1)

donde V es la tension en voltios, I la corriente en amperios y R la resistencia en ohmios. De ella se derivan:

    I = V / R    (2)
    R = V / I    (3)

Implementacion en el codigo (`scripts/electric/electrical_consumer.gd:293-297`):

    func calculate_current() -> float:
        if equivalent_resistance > 0.0 and equivalent_resistance != INF:
            return voltage_in / equivalent_resistance
        return 0.0

La proteccion contra division por cero y contra el centinela de circuito abierto `INF` (infinito de GDScript) es **obligatoria**: cuando un dispositivo esta apagado o quemado, su `equivalent_resistance` se asigna a `INF` para forzar I = 0 sin necesidad de branching.

### 2.2 Potencia electrica
La potencia aparente entregada a una carga es:

    P_apparent = V * I    (4)

La potencia real (que realiza trabajo util) se modela introduciendo el factor de potencia cos(phi) y la eficiencia eta:

    P_real = V * I * cos(phi) * eta    (5)

Implementacion (`electrical_consumer.gd:271-274`):

    var apparent_power = voltage_in * current_draw
    var real_power = apparent_power * power_factor

> **Nota:** en este simulador, "potencia" se calcula siempre pero se usa mas como metadato informativo que como variable de control. La disipacion termica del cable depende de la corriente (I), no de la potencia (P).

### 2.3 Leyes de Kirchhoff
La propagacion del simulador respeta ambas leyes de forma implicita:

- **KCL (Ley de Corrientes de Kirchhoff):** en cada nodo, la suma de corrientes entrantes es igual a la suma de corrientes salientes. Esto se implementa cuando un `ElectricalWire` suma el `current_draw` de todos sus hijos (`electrical_wire.gd:51-66`).
- **KVL (Ley de Tensiones de Kirchhoff):** en cada lazo, la suma de tensiones es cero. En la practica el simulador no tiene lazos (topologia de arbol, ver Capitulo 4), asi que KVL se reduce a la resta sucesiva de caidas de tension a lo largo de la cadena serie.

### 2.4 Equivalente de Thevenin de la red publica
La fuente `ElectricalSource` no es una fuente de tension ideal. Modela la red publica como un equivalente de Thevenin: una fuente ideal V_supply en serie con una impedancia Z_source.

    V_out = V_supply - I_total * Z_source    (6)

con Z_source = 0.5 ohmios por defecto (`electrical_source.gd:11`). Esto produce una corriente de cortocircuito teorica de:

    I_sc = V_supply / Z_source = 220 / 0.5 = 440 A    (7)

valor realista para una instalacion residencial (rango tipico 200-1000 A). El VSlider que controla V_supply va de 110 V a 280 V en pasos de 10 V (configurado en `main_engine.tscn:119-122`), cubriendo desde brownout severo hasta sobretension peligrosa.

Implementacion (`electrical_source.gd:32-54`):

    func update_network() -> void:
        var total_system_current: float = 0.0
        for child in connected_components:
            if child != null:
                child.update_electrical_state(supply_voltage)
                total_system_current += child.current_draw
        voltage_in = clamp(supply_voltage - total_system_current * source_impedance,
                           0.0, supply_voltage)
        total_system_current = 0.0
        for child in connected_components:
            if child != null:
                child.update_electrical_state(voltage_in)
                total_system_current += child.current_draw
        current_draw = total_system_current

El `clamp` final evita tensiones negativas (regeneracion imposible) o superiores a la nominal (imposible en Thevenin ideal).

### 2.5 Modelo resistivo de cable (AWG)
La resistividad del cobre a 25 C es rho = 1.68e-8 ohm*m, pero el simulador usa una tabla precargada para los calibres mas comunes en instalaciones residenciales (`electrical_wire.gd:21-25`):

    const AWG_SPECS = {
        0: {"ohms_per_meter": 0.00828, "max_amps": 15.0}, # 14 AWG
        1: {"ohms_per_meter": 0.00521, "max_amps": 20.0}, # 12 AWG
        2: {"ohms_per_meter": 0.00327, "max_amps": 30.0}  # 10 AWG
    }

Estos valores son los estandar ASTM B258 / NEC Capitulo 9 Tabla 8 para cable de cobre a 25 C. La resistencia total del cable es:

    R_wire = rho_per_m(AWG) * L    (8)

donde L es la longitud en metros (`length_meters`, exportada con default 5.0).

La cada de tension (modelada como resistor serie puro, sin reactancia) es:

    delta_V = I * R_wire    (9)

Implementacion (`electrical_wire.gd:51-66`):

    current_draw = total_current_demanded
    voltage_drop = current_draw * wire_resistance
    var voltage_out = voltage_in - voltage_drop
    if voltage_drop > 0.1:
        for child in connected_components:
            if child != null:
                child.update_electrical_state(voltage_out)

> **Limitacion declarada:** no se modela el coeficiente de temperatura del cobre (alfa = 0.00393 / C). En la realidad, un cable caliente tiene mayor resistencia; aqui la R es constante.

### 2.6 Modelo de carga (resistencia equivalente)
Para una carga especificada por su voltaje nominal V_nom, potencia nominal P_nom, factor de potencia cos(phi) y eficiencia eta, su resistencia DC equivalente es:

    R = (V_nom^2 * cos(phi) * eta) / P_nom    (10)

Implementacion (`electrical_consumer.gd:82-87`):

    if nominal_power > 0:
        internal_resistance = pow(nominal_voltage, 2) * power_factor * efficiency / nominal_power
        equivalent_resistance = internal_resistance
    else:
        internal_resistance = 0.0

Cuando cos(phi) = 1 y eta = 1 (carga resistiva pura ideal), la formula colapsa a R = V^2/P, conocida coloquialmente como "ley de watts".

> **Limitacion declarada:** una carga puramente inductiva (motor) o capacitiva no puede modelarse fielmente en DC. El factor de potencia se aplica como un multiplicador "fudge" que reduce la potencia real pero no introduce desfase. Para un motor real, esto significa que su corriente de arranque estimada es menor que la real.

### 2.7 Limitaciones declaradas
El propio proyecto reconoce, en el archivo `scripts/pedagogical_overlay.gd:11-24`, las siguientes simplificaciones del modelo:

1. **Modelo DC, sin reactancias** (X_L, X_C = 0).
2. **Cargas resistivas por defecto.** Para modelar motores, ajustar `power_factor < 1.0`.
3. **Breaker protege contra corriente, no contra sobretension.** La sobretension la maneja el regulador.
4. **Jerarquia correcta:** Fuente -> Regulador -> Breaker principal -> Breakers de rama -> Cargas.
5. **Modelo termico del cable:** sigma = I/I_max instantaneo (sin tau_termico de integracion).
6. **Impedancia de fuente 0.5 ohmios:** tipica de Thevenin de red publica.
7. **Sistema monofasico + derivado bifasico** (no trifasico).
8. **Corriente de neutro computada, no medida** (magnitud escalar, no fasorial).
9. **Para analisis real usar:** SPICE, ETAP, OpenDSS.

---

## 3. ARQUITECTURA DEL SIMULADOR

### 3.1 Diagrama de clases
El siguiente diagrama muestra la jerarquia completa de clases GDScript del simulador:

```
+---------------------------------+
|          Node2D                 |  (Godot built-in)
+---------------------------------+
              ^
              |
+---------------------------------+
|    ElectricalComponent          |  class_name, abstract base
|    (scripts/electric/           |  - voltage_in
|     electrical_component.gd)    |  - current_draw
|                                 |  - equivalent_resistance = INF
|    Metodos virtuales:           |  - get_debug_text()
|    - get_debug_text()           |  - set_details_visible(bool)
|    - update_electrical_state()  |
|    - set_details_visible()      |
+---------------------------------+
   ^      ^       ^      ^      ^      ^      ^
   |      |       |      |      |      |      |
   |      |       |      |      |      |      +---------------------------------+
   |      |       |      |      |      |      | ElectricalSplitPhasePanel     |
   |      |       |      |      |      |      | (electrical_split_phase_panel) |
   |      |       |      |      |      |      +---------------------------------+
   |      |       |      |      |      |                       ^
   |      |       |      |      |      |                       |
   |      |       |      |      |      |      +---------------------------------+
   |      |       |      |      |      |      | ElectricalDistributionPanel    |
   |      |       |      |      |      |      | (electrical_distribution_panel) |
   |      |       |      |      |      |      +---------------------------------+
   |      |       |      |      |      |
   |      |       |      |      |      +---------------------------------+
   |      |       |      |      |      | VoltageRegulator                |
   |      |       |      |      |      | (voltage_regulator.gd)          |
   |      |       |      |      |      +---------------------------------+
   |      |       |      |      |
   |      |       |      |      +---------------------------------+
   |      |       |      |      | ElectricalBreaker                 |
   |      |       |      |      | (electrical_breaker.gd)           |
   |      |       |      |      +---------------------------------+
   |      |       |      |
   |      |       |      +---------------------------------+
   |      |       |      | ElectricalConsumer                |
   |      |       |      | (electrical_consumer.gd)           |
   |      |       |      +---------------------------------+
   |      |       |
   |      |       +---------------------------------+
   |      |       | ElectricalWire                   |
   |      |       | (electrical_wire.gd)             |
   |      |       +---------------------------------+
   |      |
   |      +---------------------------------+
   |      | ElectricalSource                |
   |      | (electrical_source.gd)          |
   |      +---------------------------------+
   |
   |
+---------------------------------+    +---------------------------------+
|          Node                   |    |          Line2D                  |
+---------------------------------+    +---------------------------------+
              ^                                          ^
              |                                          |
+---------------------------------+    +---------------------------------+
|    BranchCircuit                |    |    Cable                        |
|    (branch_circuit.gd)          |    |    (scripts/elements/cable.gd)  |
+---------------------------------+    +---------------------------------+

+---------------------------------+
|    CanvasLayer (layer=100)      |
+---------------------------------+
              ^
              |
+---------------------------------+
|    PedagogicalOverlay           |
|    (pedagogical_overlay.gd)     |
+---------------------------------+
```

### 3.2 Composicion logica/visual
Un patron crucial del proyecto es la separacion entre la logica matematica y la representacion visual. Ejemplo paradigmatico: el cable electrico.

`scenes/electric/common_cable.tscn` contiene dos nodos:
- **Nodo raiz:** `Node2D` con script `electrical_wire.gd` (la logica: resistencia, caida de tension, estres termico).
- **Nodo hijo:** `Line2D` con script `cable.gd` (la visual: color, temblor).

El `Line2D` se configura con `top_level = true` (`common_cable.tscn:13`). Esto significa que su `position` se interpreta en coordenadas globales, no locales. Razon: si se arrastra el nodo raiz en el editor, las coordenadas locales del `Line2D` no se duplican con la transformacion del padre, evitando el "doble desplazamiento" mencionado en `AGENTS.md` seccion 2.

La visual lee el estado de la logica una vez por frame:

    var stress = electrical_wire.thermal_stress
    var color = stress_gradient.sample(clamp(stress, 0.0, 1.0))
    self.default_color = color
    if stress > 1.0:
        position = original_position + Vector2(randf_range(-amp, +amp), ...)

### 3.3 Sistema de grupos
Godot SceneTree Groups ("grupos") son el mecanismo principal de comunicacion desacoplada. El simulador define cuatro:

| Grupo              | Donde se anyade                                  | Quien lo consume                                  |
|--------------------|--------------------------------------------------|---------------------------------------------------|
| `power_sources`    | `electrical_source.gd:22`                        | UI master switch, toggles CheckButton, fin inrush |
| `switchable_devices` | `electrical_consumer.gd:99` (si has_switch)    | UI "Activar/Desactivar todos"                     |
| `electrical_components` | `electrical_component.gd:18` (todos)         | UI "Ver detalles" (toggle global de debug UI)    |
| `breakers`         | `electrical_breaker.gd:35`                       | (reservado, sin consumidor actual)                |

Ejemplo de uso tipico: cuando el usuario mueve el VSlider, `main_engine.gd:46` emite `Globals.global_voltage_changed(v)`. Cada `ElectricalSource` conectada a esta senal (`electrical_source.gd:21`) llama a su vez `change_supply_voltage(v)` que dispara `update_network()` en la fuente, propagandose a toda la red.

### 3.4 Senales definidas
Solo dos senales custom en todo el proyecto:

1. `Globals.global_voltage_changed(voltage: float)` (`globals.gd:3`): emitida por `main_engine.gd:46` cada vez que el usuario mueve el slider. Consumida por `ElectricalSource.change_supply_voltage`.

2. `DayNightCycle.sun_info_changed(hour: float, rotation_deg: float)` (`day_night_cycle.gd:3`): emitida cada frame. Consumida por `main_engine.gd:21` para actualizar la etiqueta de la hora solar.

### 3.5 Autoload `Globals`
`scripts/globals.gd` (5 lineas) define el unico singleton del proyecto:

    signal global_voltage_changed(voltage)
    var current_day_factor: float = 1.0

Acceso global: `Globals.global_voltage_changed.emit(220.0)` o `Globals.current_day_factor`.

`current_day_factor` es escrito por `day_night_cycle.gd:55` cada frame (coseno de 24h normalizado a [0, 1]) y leido por `electrical_consumer.gd:228` para modular la intensidad de las `PointLight2D` por la noche:

    night_boost = lerpf(1.3, 1.0, day_factor)

Asi, a medianoche las luces estan un 30% mas brillantes; a mediodia, sin boost.

### 3.6 Convenciones del proyecto
Resumen de las reglas recogidas en `AGENTS.md` seccion 6 y aplicadas consistentemente en el codigo:

- **Regla 1:** Toda subclase que override `_ready()` o `_process(delta)` debe llamar a `super._ready()` / `super._process(delta)` en la primera linea. Razon: el base `electrical_component.gd:_ready()` construye el `PanelContainer` de debug.
- **Regla 2:** Todo `CanvasLayer` o panel que sirva de fondo debe tener `Mouse -> Filter = Ignore` (`MOUSE_FILTER_IGNORE`). Si no, los `CheckButton` instanciados en el mundo 2D quedan bloqueados.
- **Regla 3:** Los `Line2D` (cables visuales) jamas deben arrastrarse desde su nodo. Su `Transform -> Position` debe permanecer en (0,0). Para mover la linea, se editan los **puntos locales** del `Line2D`, y luego se bloquea el nodo con el icono de candado.
- **Regla 4 (division por cero):** siempre que se calcule I = V / R, comprobar que R > 0 y R != INF. Si R es 0, devolver 0.0 (cortocircuito -> no calcular infinito).
- **Regla 5 (restauracion):** al restaurar un electrodomestico desde OFF, restablecer `equivalent_resistance = internal_resistance` *antes* de calcular I.

---

## 4. ALGORITMO DE SIMULACION

### 4.1 Vision general
El simulador implementa un **barrido descendente (root to leaves) de dos pasadas** sobre un arbol de componentes electricos. La convergencia se alcanza en una sola iteracion gracias a la topologia de arbol (sin ciclos), lo que permite recalcular la red completa en un solo frame.

### 4.2 Diagrama de flujo
El siguiente flowchart describe la propagacion desde la fuente hasta los consumidores:

```
[Evento disparador]
   |
   v
+---------------------+
| update_network()    |  <- llamada en ElectricalSource
+---------------------+
   |
   v
+-----------------------------+
| PASADA 1: V_supply nominal  |
+-----------------------------+
   |
   v
+---------------------------------------+
| Para cada hijo de la fuente:          |
|   child.update_electrical_state(V)    |
+---------------------------------------+
   |
   v
+---------------------------------------+
| (recursivo) Cada componente interno:  |
|   - ElectricalWire:                   |
|       V_out = V_in - I * R            |
|       propaga a hijos                 |
|   - ElectricalBreaker:                |
|       si disparado: corto abierto     |
|       si cerrado: corto ideal (V_out=V_in) |
|   - VoltageRegulator:                 |
|       clip a [V_nom*(1-b), V_nom*(1+b)]|
|   - Panel split-phase:                |
|       V_L1 = V_L2 = V_in / 2.0        |
|   - ElectricalConsumer:               |
|       evalua estado, calcula I=V/R    |
+---------------------------------------+
   |
   v
+----------------------------------------+
| Suma I_total en cada componente padre  |
+----------------------------------------+
   |
   v
+-----------------------------+
| PASADA 2: V con caida IZ    |
+-----------------------------+
   |
   v
+---------------------------------------+
| V_out_source = V_supply - I*Z_source  |
| clamp [0, V_supply]                   |
+---------------------------------------+
   |
   v
+---------------------------------------+
| Repite propagacion con V_out_source   |
| Ahora cada hijo ya tiene un I          |
| pre-calculado, pero el V es corregido  |
+---------------------------------------+
   |
   v
+--------------------------+
| Convergencia en 1 frame |
+--------------------------+
```

### 4.3 Pseudocodigo de la propagacion
El siguiente pseudocodigo resume la logica completa del barrido, con referencias a las lineas reales del codigo.

**En `electrical_source.gd:32-54`:**

    func update_network():
        # PASADA 1: propagar con V nominal
        total_I = 0
        for child in connected_components:
            child.update_electrical_state(supply_voltage)
            total_I += child.current_draw
        # Caida en Z_source (Thevenin)
        V_out = clamp(supply_voltage - total_I * source_impedance,
                      0.0, supply_voltage)
        # PASADA 2: propagar con V corregido
        total_I = 0
        for child in connected_components:
            child.update_electrical_state(V_out)
            total_I += child.current_draw
        self.current_draw = total_I
        self.voltage_in = V_out

**En `electrical_wire.gd:43-66`:**

    func update_electrical_state(received_voltage):
        self.voltage_in = received_voltage
        # Sumar corrientes demandadas por hijos
        total_I = 0
        for child in connected_components:
            if child != null:
                child.update_electrical_state(received_voltage)
                total_I += child.current_draw
        # Caida de tension en el cable
        V_drop = total_I * wire_resistance
        self.current_draw = total_I
        self.voltage_drop = V_drop
        self.thermal_stress = total_I / max_current
        # Re-propagar hijos con V corregido si la caida es significativa
        if V_drop > 0.1:
            V_out = received_voltage - V_drop
            for child in connected_components:
                if child != null:
                    child.update_electrical_state(V_out)
        # Logs de estres
        if thermal_stress > 1.2:
            push_warning("FUNDIDO")
        elif thermal_stress > 1.0:
            push_warning("sobrecargado")

**En `electrical_consumer.gd:114-196` (hoja del arbol):**

    func update_electrical_state(received_voltage):
        self.voltage_in = received_voltage
        previous_state = current_state
        # Determinar thresholds
        V_burnout = nominal_voltage * burnout_percent
        V_over    = nominal_voltage * max_safe_percent
        V_under   = nominal_voltage * min_safe_percent
        V_cutoff  = nominal_voltage * effective_cutoff
        # Cascada de decision
        if voltage_in > V_burnout:
            current_state = BROKEN
            equivalent_resistance = INF
            current_draw = 0.0
            if toggle_button: toggle_button.disabled = true
        elif voltage_in > V_over:
            current_state = OVERVOLTAGE
            current_draw = calculate_current()
        elif voltage_in >= V_under and voltage_in <= V_over:
            current_state = NORMAL
            current_draw = calculate_current()
        elif voltage_in >= V_cutoff and voltage_in < V_under:
            current_state = UNDERVOLTAGE
            current_draw = calculate_current()
        else:
            current_state = OFF
            equivalent_resistance = INF
            current_draw = 0.0
        # Inrush
        if simulation_started and previous_state == OFF
           and current_state != OFF and current_state != BROKEN:
            if not is_inrush_active:
                is_inrush_active = true
                _handle_inrush_timer()

### 4.4 Justificacion de la convergencia en un paso
La topologia de la red electrica en el simulador es estrictamente un **arbol** (no hay ciclos). Esto es una decision de diseno deliberada: cualquier conexion mallada requeriria resolver un sistema de ecuaciones lineales (matriz de admitancias) en cada paso.

Para un sistema lineal de N ecuaciones, el metodo de Gauss-Seidel converge en exactamente **una iteracion** si y solo si la matriz de coeficientes es triangular inferior (lo cual es cierto para un arbol dirigido). En el caso del simulador:

- La unica "no linealidad" es el comportamiento de los consumidores (estado BROKEN corta la corriente, estado NORMAL la permite).
- Las protecciones (breakers, reguladores) tienen histeresis cero en el modelo actual.

Por lo tanto, **una doble pasada es suficiente para alcanzar el punto fijo**.

### 4.5 Puntos de invocacion de `update_network`
La red se recalcula completa cuando ocurre cualquiera de estos eventos:

| Disparador                                       | Codigo                                       |
|--------------------------------------------------|----------------------------------------------|
| Escena recien cargada                            | `electrical_source.gd:24` (`call_deferred`) |
| Usuario mueve el VSlider                        | `main_engine.gd:46` -> `Globals` -> fuente   |
| Usuario togglea un CheckButton local             | `electrical_consumer.gd:110-112`             |
| Finaliza el periodo de inrush de un consumidor   | `electrical_consumer.gd:196`                 |
| UI "Activar/Desactivar todos"                    | `main_engine.gd:57-59`                       |
| UI "Reiniciar SIM"                               | `main_engine.gd:49` (recarga la escena)      |
| Reset de breakers programatico                   | `electrical_distribution_panel.gd:129, 142`  |

La doble pasada es **solo dentro de la fuente**. Los cables internos solo hacen una propagacion local con re-propagacion si la caida supera 0.1 V (umbral arbitrario para evitar actualizaciones redundantes).

---

## 5. MODELO DEL CONSUMIDOR (ELECTRICALCONSUMER)

### 5.1 Parametros nominales
Cada electrodomestico en el simulador se describe por:

- **nominal_voltage** (V): tension de placa. Default 110 V (sistema argentino) o 220 V (bifasico). Exportada como float.
- **nominal_power** (W): potencia nominal. Si vale 0, la resistencia interna se asigna a 0 (cortocircuito virtual).
- **power_factor** (cos(phi)): factor de potencia. Default 1.0 (carga resistiva).
- **efficiency** (eta): rendimiento. Default 1.0.
- **device_class**: enum con valores INCANDESCENT, MOTOR, COMPRESSOR, SMPS, MIXED. Determina el perfil de inrush y el corte por subtension.
- **min_power_on_percent** (default -1): umbral de encendido. Si es -1, usa la tabla `CLASS_CUTOFF`.
- **min_safe_percent** (default 0.90): limite inferior de la zona NORMAL.
- **max_safe_percent** (default 1.05): limite superior de la zona NORMAL.
- **burnout_percent** (default 1.25): tension por encima de la cual el dispositivo se dana permanentemente.
- **inrush_multiplier** (default -1): factor de corriente de arranque. Si -1, usa el perfil de la clase.
- **inrush_duration** (default -1): duracion del inrush en segundos.
- **has_switch** (default false): si true, instancia un `CheckButton` en el mundo 2D y se anyade al grupo `switchable_devices`.
- **is_switched_on** (default true): estado logico del interruptor.

### 5.2 Calculo de resistencia interna
La formula (10) aplicada al consumidor es:

    R_int = (V_nom^2 * cos(phi) * eta) / P_nom

Implementacion literal en `electrical_consumer.gd:82-87`.

### 5.3 Maquina de estados
Los cinco estados son mutuamente excluyentes y se evaluan en cascada sobre la tension de entrada `V_in` y los thresholds de la seccion 5.1.

```
                    V_in > V_burnout
                    (default 1.25 * V_nom)
        +---------------------------------+
        |                                 v
   [OFF] ---- V_in < V_cutoff ----> [BROKEN]   (permanente)
        |                                 ^
        | V_in >= V_cutoff                |
        v                                 |
  [UNDERVOLTAGE] --- V_in >= V_under ---> |
        |                                 |
        v                                 |
   [NORMAL] --- V_in > V_over ----> [OVERVOLTAGE]
        |                          |
        +--------------------------+
        (cuando V_in vuelve a <= V_over)
```

Estados definidos en `electrical_consumer.gd` (enum `DeviceState`):

| Estado        | V_in (relativo a V_nom) | R_eq            | I_draw       | Sprite tint    | Jitter | Luz       |
|---------------|-------------------------|------------------|--------------|----------------|--------|-----------|
| OFF           | < V_cutoff              | INF              | 0            | gris (0.3)     | 0      | disabled  |
| UNDERVOLTAGE  | V_cutoff <= V < V_under | R_int            | V/R_int      | amarillo (0.6) | 0      | dim + 0.5x|
| NORMAL        | V_under <= V <= V_over  | R_int            | V/R_int      | blanco         | 0      | normal    |
| OVERVOLTAGE   | V_over < V <= V_burnout | R_int            | V/R_int      | naranja        | 1 px   | brighter  |
| BROKEN        | > V_burnout             | INF              | 0            | rojo           | 4 px   | disabled  |

Tabla de umbrales por clase (`CLASS_CUTOFF`, `electrical_consumer.gd:22-28`):

| Clase         | V_cutoff (fraccion de V_nom) |
|---------------|------------------------------|
| INCANDESCENT  | 0.60 (60%)                   |
| MOTOR         | 0.85 (85%)                   |
| COMPRESSOR    | 0.85 (85%)                   |
| SMPS          | 0.80 (80%)                   |
| MIXED         | 0.80 (80%)                   |

### 5.4 Modelo de inrush
Al transicionar de OFF a cualquier estado activo, el consumidor multiplica su corriente por un factor durante una ventana de tiempo. Esto modela la corriente de arranque, que en la realidad puede ser 5-10x la nominal durante fracciones de segundo a pocos segundos.

Tabla de perfiles (`INRUSH_PROFILES`, `electrical_consumer.gd:48-54`):

| Clase         | Multiplicador | Duracion (s) | Justificacion real                       |
|---------------|---------------|--------------|------------------------------------------|
| INCANDESCENT  | 12.0          | 0.15         | filamento frio: R baja, I sube x10-15   |
| MOTOR         | 6.0           | 2.0          | rotor bloqueado: corriente de arranque   |
| COMPRESSOR    | 6.0           | 0.5          | similar al motor, mas breve              |
| SMPS          | 2.0           | 0.1          | carga de condensadores de bulk           |
| MIXED         | 2.5           | 0.5          | caso general                             |

La activacion esta protegida por una bandera `simulation_started` que se activa 0.2 s despues de `_ready` (`electrical_consumer.gd:108`). Esto evita que la primera propagacion de la red (donde todos los consumidores pasan de OFF a su estado nominal) dispare inrush simultaneo en todos ellos.

Cuando la ventana de inrush termina, `_handle_inrush_timer` (`electrical_consumer.gd:188-196`) emite una llamada al grupo `power_sources` para recalcular la red:

    get_tree().call_group("power_sources", "update_network")

Esto significa que los cables veran un pico de corriente durante el inrush y luego una estabilizacion.

### 5.5 No autoreparacion
Un consumidor en estado BROKEN permanece en el para siempre. Su `equivalent_resistance` se asigna a `INF` (cortocircuito abierto) y su `CheckButton` se deshabilita (`electrical_consumer.gd:147`). El unico camino para "reparar" la red es recargar la escena con el boton "Reiniciar SIM" (`main_engine.gd:49`), lo que destruye y recrea todo el arbol electrico.

> **Decision de diseno:** se prioriza la fidelidad al fallo fisico real. Un electrodomestico quemado no se repara solo.

---

## 6. MODELO DEL CABLE Y ESTRES TERMICO

### 6.1 Tabla AWG implementada
La siguiente tabla, hardcodeada en `electrical_wire.gd:21-25`, define la resistividad por metro y la ampacidad maxima de los tres calibres de cable disponibles en el editor:

| Indice enum | Calibre  | rho (ohm/m)   | I_max (A) | Seccion (mm^2) | Aplicacion tipica       |
|-------------|----------|---------------|-----------|----------------|-------------------------|
| 0           | 14 AWG   | 0.00828       | 15        | 2.08           | Alumbrado               |
| 1           | 12 AWG   | 0.00521       | 20        | 3.31           | Tomas generales         |
| 2           | 10 AWG   | 0.00327       | 30        | 5.26           | Tomas de alta demanda   |

Estos valores son los estandar NEC Tabla 8 (2020) para cobre a 25 C. En el archivo de escena `main_engine.tscn`, los cuatro cables principales de las casas usan `wire_gauge = 2` (10 AWG, 30 A).

### 6.2 Formulas del modelo
Para un cable de longitud L y calibre AWG dado:

    R_wire = rho_per_m(AWG) * L                              (11)
    delta_V = I_total * R_wire                               (12)
    sigma   = I_total / I_max(AWG)                           (13)

Implementacion (`electrical_wire.gd:30-32`, `:51-55`).

### 6.3 Mensajes de log
El cable emite advertencias a la consola segun el nivel de estres:

    if thermal_stress > 1.2:
        push_warning("FUNDIDO")     # mas del 120% de su capacidad
    elif thermal_stress > 1.0:
        push_warning("sobrecargado")# entre 100% y 120%

> **Limitacion declarada:** el cable no se dana realmente ni se autodestruye. La visualizacion (gradiente + shake) es la unica consecuencia del estres. No hay integracion termica con tau, asi que un pulso breve de 5x la capacidad no deja "memoria" de calor.

### 6.4 Visualizacion del cable
La clase `Cable` (visual) lee `electrical_wire.thermal_stress` cada frame (`scripts/elements/cable.gd:21-43`) y:

1. **Color:** muestrea un `Gradient` recurso (`resources/cable_gradient.tres`) en el offset `clamp(stress, 0, 1)`. El gradiente va de verde (0.0) a naranja-rojo (1.0).
2. **Shake (sigma > 1.0):** la amplitud en pixeles es `2.0 * (sigma - 1.0)`, aplicada a `position` del `Line2D` con `randf_range(-amp, +amp)` en ambos ejes.

Tabla de mapeo:

| sigma  | Color      | Amplitud shake (px) |
|--------|------------|---------------------|
| 0.0    | verde      | 0                   |
| 0.5    | amarillo   | 0                   |
| 0.8    | naranja    | 0                   |
| 1.0    | rojo       | 0                   |
| 1.1    | rojo       | 0.2                 |
| 1.5    | rojo       | 1.0                 |
| 2.0    | rojo       | 2.0                 |

---

## 7. MODELO DE PROTECCIONES

### 7.1 Breaker IEC 60898
El simulador implementa las protecciones termomagneticas segun el estandar IEC 60898 (utilizado en disyuntores domesticos residenciales). La logica esta duplicada intencionalmente en dos archivos:

- `scripts/electric/electrical_breaker.gd` (standalone, sin uso actual en escena).
- `scripts/electric/branch_circuit.gd:53-91` (usado por `ElectricalDistributionPanel`).

**Disparo magnetico (instantaneo):** compara la corriente contra un multiplo de la nominal segun la curva del breaker:

| Curva (enum) | Multiplicador M | Rango IEC     | Uso tipico                  |
|--------------|-------------------|---------------|------------------------------|
| 0 (B)        | 4.0               | 3-5 In        | Cargas resistivas            |
| 1 (C)        | 7.5               | 5-10 In       | Tomas generales, mixto        |
| 2 (D)        | 15.0              | 10-20 In      | Motores, transformadores     |

Implementacion (`electrical_breaker.gd:62-77`):

    var ratio = current_draw / rated_current
    var magnetic_threshold = MAGNETIC_MULTIPLIERS[magnetic_curve]
    if ratio >= magnetic_threshold:
        _trip("CORTOCIRCUITO")
        return

**Disparo termico (I^2t, tiempo inverso):** un integral de tiempo se acumula mientras la corriente supera 1.13 In. El integral se compara contra umbrales escalonados:

| Banda de ratio  | Tiempo de disparo | Limite IEC tipico  |
|------------------|-------------------|---------------------|
| 1.13 < r < 1.30  | 14400 s (4 h)     | 1 h a 2 h          |
| 1.30 <= r < 1.45 | 3600 s (1 h)      | 30 min a 1 h       |
| r >= 1.45        | 600 s (10 min)    | < 30 min            |

Implementacion (`electrical_breaker.gd:64-89`):

    if ratio > THERMAL_THRESHOLD_1:  # 1.13
        overload_integral += delta
    if ratio > THERMAL_THRESHOLD_2:  # 1.30
        overload_integral += delta
    if ratio > THERMAL_THRESHOLD_3:  # 1.45
        overload_integral += delta
    if overload_integral >= thermal_time:
        _trip("SOBRECARGA TERMICA")

**Enfriamiento:** cuando `ratio <= 1.13`, el integral decrece a la mitad de la velocidad de carga:

    overload_integral = max(0.0, overload_integral - delta * 0.5)

Esto modela el enfriamiento real del bimetal, que es aproximadamente la mitad de rapido que el calentamiento.

### 7.2 Regulador de voltaje (AVR)
El regulador (`scripts/electric/voltage_regulator.gd`) modela un estabilizador electronico de voltaje (Automatic Voltage Regulator). Su comportamiento es idealizado: no tiene tiempo de respuesta, no tiene historesis.

Parametros exportados:
- **nominal_voltage** (default 220 V): tension de salida nominal.
- **regulation_band** (default 0.10, rango 0.01-0.25): tolerancia porcentual.
- **blackout_threshold** (default 0.5, 0 desactiva): fraccion de V_nom por debajo de la cual se considera blackout total.

Logica de salida (`voltage_regulator.gd:40-69`):

| Condicion                       | V_out              | Modo string       |
|---------------------------------|--------------------|-------------------|
| V_in >= V_nom * blackout_th     | V_nom * (1 + band) | CLIPPING_HIGH     |
| V_in <= V_nom * (1 - band)      | V_nom * (1 - band) | CLIPPING_LOW      |
| V_in < V_nom * blackout_th      | 0.0                | BLACKOUT          |
| Dentro de la banda              | V_in               | NORMAL            |

Modos stringificados se exponen a traves de la propiedad `regulation_mode` para que la UI pueda colorear el sprite segun corresponda.

### 7.3 Jerarquia correcta de protecciones
El propio proyecto advierte (en `pedagogical_overlay.gd` y en comentarios del codigo) sobre la jerarquia canonica:

    Fuente -> Regulador -> Breaker principal -> Breakers de rama -> Cargas

Razones:
1. El **regulador** maneja **sobretension y subtension** (problemas de voltaje).
2. El **breaker** maneja **sobrecorriente** (cortocircuito y sobrecarga).
3. Un breaker NO protege contra sobretension sostenida (su disparo termico responde a I, no a V).
4. Un regulador NO protege contra cortocircuito (su limitacion es de voltaje, no de corriente).

Colocar el breaker antes del regulador (orden inverso) es un error de diseno: una sobrecorriente en las cargas dispararia el breaker aguas arriba antes de que el regulador pueda estabilizar la tension.

---

## 8. PANEL SPLIT-PHASE Y DISTRIBUCION

### 8.1 Topologia split-phase
El sistema split-phase (tambien llamado "monofasico con neutro derivado" o "centro de TAP") se usa en Americas del Norte (120/240 V) y en Argentina (220 V bifasico). Consiste en:

- Un transformador con punto medio en el secundario.
- Dos lineas activas: L1 y L2 (180 grados fuera de fase en la realidad).
- Un neutro conectado al punto medio.
- Cargas de 110 V conectadas entre L1-N o L2-N.
- Cargas de 220 V conectadas entre L1-L2.

### 8.2 Modelo matematico del simulador
En `electrical_split_phase_panel.gd:19-59`, la division es puramente escalar:

    var single_phase_voltage = voltage_in / 2.0
    for child in phase_1_components:
        child.update_electrical_state(single_phase_voltage)
        phase_1_current += child.current_draw
    # ... mismo para phase_2 ...
    for child in biphasic_components:
        child.update_electrical_state(voltage_in)
        biphasic_current += child.current_draw
    neutral_current = abs(phase_1_current - phase_2_current)
    current_draw = max(phase_1_current, phase_2_current) + biphasic_current

> **Limitacion declarada:** en la realidad, las corrientes L1 y L2 son fasores opuestos (180 grados de desfase), por lo que la corriente de neutro es la suma fasorial, no la resta escalar. Cuando L1 y L2 estan equilibradas (mismas cargas), la corriente de neutro real es casi cero. La formula `abs(L1 - L2)` da el mismo resultado en ese caso particular, pero diverge en regimenes desbalanceados con cargas reactivas.

### 8.3 `ElectricalDistributionPanel` (panel con breakers)
`ElectricalDistributionPanel` (`electrical_distribution_panel.gd`) extiende `ElectricalSplitPhasePanel` y reemplaza las listas planas de componentes por listas de `BranchCircuit`:

    phase_1_circuits: Array[BranchCircuit]
    phase_2_circuits: Array[BranchCircuit]
    biphasic_circuits: Array[BranchCircuit]

Un `BranchCircuit` (`branch_circuit.gd`) agrupa:
- Un breaker (con `rated_current` y `magnetic_curve` propios).
- Una lista de cargas downstream (`connected_components`).
- Su propio `propagate(voltage, delta)` que internamente decide si dispara.

La propagacion se hace asi (`electrical_distribution_panel.gd:58-92`):

    func update_electrical_state(received_voltage):
        # Propaga cada BranchCircuit y suma corrientes
        var total_I = 0.0
        for circuit in phase_1_circuits:
            total_I += circuit.propagate(single_phase_v, delta)
        # ... mismo para phase_2 y biphasic ...
        neutral_current = abs(phase_1_I - phase_2_I)
        self.current_draw = max(phase_1_I, phase_2_I) + biphasic_I

### 8.4 Cuando usar cada panel
- **`ElectricalSplitPhasePanel`:** casas con pocas cargas por fase y sin proteccion individual (todo va por un unico breaker general).
- **`ElectricalDistributionPanel`:** casas con circuitos separados (iluminacion, tomas, cocina, aire acondicionado), cada uno con su breaker termomagnetico.

En `scenes/main_engine.tscn`, la casa 1 usa `ElectricalDistributionPanel` con `BranchCircuit` por fase; las casas 2, 3 y 4 usan `ElectricalSplitPhasePanel` con componentes sueltos.

---

## 9. SISTEMA DE FEEDBACK VISUAL (GAME FEEL)

### 9.1 Principios de diseno
El simulador no solo calcula valores: los **hace visibles**. El objetivo es que el usuario "sienta" los fenomenos electricos sin necesidad de un multímetro. Tres canales sensoriales:

1. **Color (Sprite2D modulate):** estado logico -> tinte.
2. **Movimiento (position jitter):** inestabilidad mecanica -> vibracion.
3. **Luz (PointLight2D energy):** estado electrico -> luminosidad + parpadeo.

### 9.2 Mapeo estado -> visual del consumidor
Tabla completa del mapeo implementado en `electrical_consumer.gd:198-265`:

| Estado        | Sprite2D.modulate   | Position offset      | PointLight2D                                          |
|---------------|---------------------|----------------------|--------------------------------------------------------|
| OFF           | Color(0.3, 0.3, 0.3)| original             | disabled                                               |
| UNDERVOLTAGE  | Color(0.6, 0.6, 0.4)| original             | enabled, color = orig * (0.6, 0.6, 0.4), scale * 0.5 |
| NORMAL        | Color.WHITE         | original             | enabled, color = orig, scale = orig                    |
| OVERVOLTAGE   | Color(1.0, 0.6, 0.2)| orig + randf(-1, +1) | enabled, color = orig * (1.0, 0.6, 0.2), jitter       |
| BROKEN        | Color.RED           | orig + randf(-4, +4) | disabled                                               |

### 9.3 Modulacion de la luz
La energia de la `PointLight2D` se calcula como:

    energy = (orig * voltage_ratio) * flicker_mult * night_boost

Donde:
- `voltage_ratio = V_in / V_nom` (dependencia lineal del voltaje real).
- `flicker_mult`: 1.0 en NORMAL; `randf_range(0.8, 0.95)` en UNDERVOLTAGE; `randf_range(1.0, 1.2)` en OVERVOLTAGE; `randf_range(0.8, 1.4)` durante inrush.
- `night_boost = lerpf(1.3, 1.0, day_factor)` (1.3 a medianoche, 1.0 a mediodia).

Esto da una sensacion cuantitativa: una lampara bajo voltaje esta tenue y parpadea, una sobre voltaje esta brillante y tiembla, una quemada esta apagada y tiembla violentamente.

### 9.4 Chart de voltaje en la UI
`main_engine.gd:90-125` dibuja un grafico de la tension de la fuente en tiempo real:
- **Banda segura:** 190-250 V (verde, dentro del +-14% de 220 V).
- **Linea amarilla de referencia:** 220 V exactos (alfa 0.2).
- **Rejilla:** cada 20 V, mas fuerte cada 40 V.
- **Historial:** `PackedFloat32Array` de tamano 80 (`HISTORY_SIZE = 80`), muestreado cada 0.15 s (`SAMPLE_INTERVAL = 0.15`).

Esto da al usuario una vision retrospectiva: "hace 12 segundos el voltaje cayo a 180 V durante 3 segundos, probablemente por un pico de consumo".

### 9.5 Boost nocturno
El ciclo dia/noche (`scripts/day_night_cycle.gd`) calcula un factor cosenoidal de 24h normalizado a [0, 1] y lo escribe en `Globals.current_day_factor`. Esto se usa para:

- Modular la energia de las `PointLight2D` (`electrical_consumer.gd:228`): a medianoche, las lamparas se ven mas impactantes (boost x1.3).
- Tintear el fondo con `CanvasModulate` y rotar la `DirectionalLight2D` (la posicion del sol).

La hora se puede fijar con un `CheckButton` "Fijar sol" en la UI principal, y un `HSlider` permite seleccionar la hora exacta (0-24, paso 0.1).

---

## 10. UI, CONTROLES Y CICLO DIA/NOCHE

### 10.1 Layout de la UI principal
La escena `scenes/main_engine.tscn` define la siguiente jerarquia de Control:

```
CanvasLayer (UI)
   |
   +-- Panel (VSlider 110-280V)
   +-- CheckButton "Ver detalles"
   +-- CheckButton "Activar/Desactivar todos"
   +-- Button "Reiniciar SIM"
   +-- Chart (Control custom, dibuja historial de voltaje)
   +-- HSlider (hora del dia, 0-24)
   +-- CheckButton "Fijar sol"
   +-- Label "sun_angle_label"
   +-- TextureRect "VoltageGradientBg" (fondo decorativo)

world (Node2D, contiene el mundo electrico)
   +-- ParallaxBackground
   +-- DayNightCycle
   +-- 4 x "casa*" (cada una con su cableado)
       +-- ElectricalSource (solo uno, en Electrics)
       +-- ElectricalWire x N
       +-- ElectricalSplitPhasePanel o ElectricalDistributionPanel
       +-- ElectricalConsumer x N
```

### 10.2 VSlider de voltaje
Rango: 110 V a 280 V, paso 10 V, valor inicial 220 V.
Senial conectada: `value_changed -> _on_v_slider_value_changed` (`main_engine.gd:44-46`).
Accion: emite `Globals.global_voltage_changed(v)`.
Consumidor: `ElectricalSource.change_supply_voltage(v)` (`electrical_source.gd:21`).

### 10.3 Botones globales

| Control                          | Accion                                                                  |
|----------------------------------|-------------------------------------------------------------------------|
| Button "Reiniciar SIM"           | `get_tree().reload_current_scene()` (`main_engine.gd:49`)              |
| CheckButton "Ver detalles"       | `get_tree().call_group("electrical_components", "set_details_visible", toggled_on)` |
| CheckButton "Activar/Desactivar todos" | `set_switch_state_externally(toggled_on)` a `switchable_devices` + `update_network` |

### 10.4 `PedagogicalOverlay`
CanvasLayer en `layer = 100`, adjuntado programaticamente al inicio (`main_engine.gd:23` -> `PedagogicalOverlay.create_and_attach(self)`). Toggle con tecla `H`.

Muestra un panel con el texto completo del disclaimer del modelo, explicitando que se aproxima y que se ignora (ver Capitulo 2.7). Es la "tarjeta de modelo" (model card) del simulador: dice al usuario que no es SPICE y por que.

> **Proteccion de mouse:** el panel tiene `mouse_filter = MOUSE_FILTER_IGNORE` (`pedagogical_overlay.gd:50`) para no bloquear los `CheckButton` del mundo 2D.

### 10.5 `DayNightCycle`
`scripts/day_night_cycle.gd` (autocontenido, no toca la red electrica):
- Acumula `elapsed_seconds` cada frame.
- Calcula `hour = fmod(elapsed_seconds / 3600.0, 24.0)`.
- Calcula `day_factor = (1.0 - cos(2*PI*hour/24.0)) / 2.0` (1 a medianoche, 0 a mediodia).
- Calcula `rotation_deg = -90.0 + (hour / 24.0) * 360.0` (el sol gira).
- Emite `sun_info_changed(hour, rotation_deg)`.
- Escribe `Globals.current_day_factor = day_factor`.

Permite fijar el sol con un `CheckButton` y seleccionar la hora exacta con un `HSlider`.

### 10.6 `Camera2D`
`scripts/camera.gd`:
- Pan con WASD (teclas fisicas, no logicas, via `Input.is_physical_key_pressed`).
- Drag con boton central del mouse.
- Zoom con rueda del mouse, clamped a `[min_zoom, max_zoom]`.
- Suavizado: `position = position.lerp(target_position, pan_smoothing)` con `pan_smoothing = 0.2`.
- Limites del mundo leidos de un `ReferenceRect` "world_border".

Sin relacion con la simulacion electrica; es ortogonal.

---

## 11. LIMITACIONES DECLARADAS Y HERRAMIENTAS PROFESIONALES

### 11.1 Resumen de lo que el simulador NO hace
Lista consolidada, expandida desde el disclaimer de `pedagogical_overlay.gd`:

1. **Sin reactancias inductivas/capacitivas.** No modela motores reales con su inductancia, ni factor de potencia reactivo en el sentido fasorial.
2. **Sin efecto skin.** La resistencia del cable es constante, independiente de la frecuencia.
3. **Sin coeficiente de temperatura.** El cobre no se "calienta" ni aumenta su R.
4. **Sin integracion termica del cable.** sigma es instantaneo; no hay tau de calentamiento/enfriamiento.
5. **Sin potencia compleja.** P = V*I siempre; cos(phi) es un multiplicador, no un angulo.
6. **Sin sistemas trifasicos.** Solo monofasico + bifasico derivado.
7. **Sin proteccion diferencial (GFCI/RCD).** Un breaker termomagnetico no detecta fugas a tierra.
8. **Sin persistencia del estado BROKEN.** Requiere recarga de escena.
9. **Sin autoreparacion de breakers.** Existen los metodos `reset()` y `reset_all_breakers()` pero no estan conectados a la UI.
10. **Sin mediciones fasoriales.** La corriente de neutro se calcula escalarmente.
11. **Sin analisis en regimen transitorio.** Todo es cuasi-estacionario.

### 11.2 Herramientas profesionales recomendadas
El propio disclaimer sugiere tres familias de herramientas para analisis real:

| Herramienta     | Tipo                | Caso de uso ideal                                  |
|------------------|---------------------|----------------------------------------------------|
| **SPICE** (LTspice, ngspice) | Simulador de circuito | Analisis transitorio, pequena senal, electronica  |
| **ETAP**          | Suite industrial     | Plantas industriales, corto de arco, coordinacion  |
| **OpenDSS**       | Open source          | Sistemas de distribucion, flujo de carga, Q        |

Otras herramientas relevantes:
- **PSCAD**: transitorios electromagneticos, HVDC.
- **PowerWorld Simulator**: visualizacion geografica de redes.
- **DIgSILENT PowerFactory**: analisis modal, estabilidad transitoria.
- **NEPLAN**: redes industriales y de transmision.

### 11.3 Cuando usar EMS vs. cuando migrar
- **Usar EMS** cuando: el objetivo es didactico, el tiempo es limitado, y se busca intuicion mas que cifras exactas.
- **Migrar a SPICE/ETAP** cuando: se necesita precision cuantitativa, se modelan no linealidades (saturacion magnetica, semiconductores), o se requiere certificacion normativa.
- **Migrar a OpenDSS** cuando: la red es de distribucion (media tension, multiples alimentadores) y se busca flujo de carga fasorial.

---

## 12. CONCLUSIONES Y TRABAJO FUTURO

### 12.1 Resumen del modelo
EMS es un simulador pedagogico de redes electricas residenciales que implementa:

- Un modelo DC cuasi-estacionario con Thevenin en la fuente.
- Cables modelados como resistores serie puros con tabla AWG.
- Consumidores como resistencias equivalentes con maquina de estados de 5 fases.
- Protecciones termomagneticas IEC 60898 (curvas B/C/D + I^2t).
- Reguladores AVR con clipping y blackout.
- Distribucion split-phase 220V/2x110V.
- Algoritmo de propagacion Gauss-Seidel de doble pasada, convergente en un frame.
- Visualizacion dramatica (color, vibracion, luz) que traduce valores numericos en sensaciones.

### 12.2 Balance simplicidad/realismo
El modelo sacrifica precision cuantitativa a cambio de:
- **Velocidad de calculo** (un frame para toda la red).
- **Transparencia** (el codigo GDScript es legible; el usuario puede auditar las formulas).
- **Dramatismo visual** (game feel orientado a la ensenanza).
- **Robustez** (no requiere solver numerico, no converge condicionalmente).

Esto lo hace ideal para ensenanza introductoria pero insuficiente para ingenieria de detalle.

### 12.3 Trabajo futuro (roadmap)
Posibles extensiones ordenadas por dificultad estimada:

1. **Persistencia de estado BROKEN** en JSON, para que la simulacion "recuerde" los fallos entre sesiones.
2. **Auto-reset de breakers** con un boton UI dedicado (los metodos ya existen, falta wire-up).
3. **Indicador de corriente de neutro** visual (sprite que crece con I_neutro).
4. **THD y flicker Pst** (indicadores de calidad de energia).
5. **Modelo termico real del cable** con integracion I^2t y constante de tiempo tau.
6. **3-fases reales** (matriz de admitancias, solucion por eliminacion gaussiana).
7. **GFCI/RCD** (proteccion diferencial, mide suma fasorial de corrientes).
8. **Reactancias** (X_L, X_C) para modelar motores y condensadores con desfase real.
9. **Curvas de demanda** (perfiles de uso por hora del dia, multiplicadas por el ciclo dia/noche).
10. **Editor visual de topologias** (drag-and-drop de componentes en el mundo 2D con auto-cableado).

### 12.4 Reflexion final
El proyecto demuestra que un simulador educativo util no requiere resolver las ecuaciones de Maxwell: basta con un modelo de circuito DC con la fenomenologia adecuada (cables, protecciones, regulador) y una presentacion visual cuidada. La eleccion del Motor Godot para este dominio es acertada: el modelo logico/visual separado se traduce de forma natural a la jerarquia de nodos, y el sistema de grupos de Godot reemplaza ventajosamente a un bus de eventos tradicional.

---

## APENDICES

### A. Tabla completa de `class_name` global registry

| Simbolo                   | Archivo                                                | Tipo base         |
|---------------------------|---------------------------------------------------------|--------------------|
| ElectricalComponent       | scripts/electric/electrical_component.gd:2             | Node2D             |
| ElectricalSource          | scripts/electric/electrical_source.gd:2                | ElectricalComponent|
| ElectricalWire            | scripts/electric/electrical_wire.gd:2                  | ElectricalComponent|
| ElectricalConsumer        | scripts/electric/electrical_consumer.gd:2              | ElectricalComponent|
| ElectricalBreaker         | scripts/electric/electrical_breaker.gd:2               | ElectricalComponent|
| VoltageRegulator          | scripts/electric/voltage_regulator.gd:2                | ElectricalComponent|
| ElectricalSplitPhasePanel | scripts/electric/electrical_split_phase_panel.gd:2     | ElectricalComponent|
| ElectricalDistributionPanel | scripts/electric/electrical_distribution_panel.gd:2  | ElectricalSplitPhasePanel |
| BranchCircuit             | scripts/electric/branch_circuit.gd:2                   | Node               |
| Cable                     | scripts/elements/cable.gd:2                            | Line2D             |
| PedagogicalOverlay        | scripts/pedagogical_overlay.gd:2                       | CanvasLayer        |

Nota: `Globals` (autoload) NO tiene `class_name`; se accede solo por el identificador de autoload.

### B. Variables @export (referencia rapida)

| Clase                       | Variable                | Default | Notas                                       |
|-----------------------------|-------------------------|---------|---------------------------------------------|
| ElectricalSource            | supply_voltage          | 220.0   | Voltaje nominal Thevenin                    |
| ElectricalSource            | source_impedance        | 0.5     | Ohmios, Z_source                            |
| ElectricalSource            | connected_components    | []      | Array[ElectricalComponent]                  |
| ElectricalWire              | wire_gauge              | 1       | 0=14AWG, 1=12AWG, 2=10AWG                   |
| ElectricalWire              | length_meters           | 5.0     | Float                                       |
| ElectricalWire              | connected_components    | []      | Array[ElectricalComponent]                  |
| ElectricalConsumer          | nominal_voltage         | 110.0   | V_placa                                     |
| ElectricalConsumer          | nominal_power           | 1000.0  | W; si 0 -> R_int = 0                        |
| ElectricalConsumer          | power_factor            | 1.0     | cos(phi)                                    |
| ElectricalConsumer          | efficiency              | 1.0     | eta                                         |
| ElectricalConsumer          | device_class            | MIXED   | enum INCANDESCENT/MOTOR/COMPRESSOR/SMPS/MIXED |
| ElectricalConsumer          | min_power_on_percent    | -1.0    | -1 = usa CLASS_CUTOFF                       |
| ElectricalConsumer          | min_safe_percent        | 0.90    | limite inferior NORMAL                      |
| ElectricalConsumer          | max_safe_percent        | 1.05    | limite superior NORMAL                      |
| ElectricalConsumer          | burnout_percent         | 1.25    | > esto = BROKEN                             |
| ElectricalConsumer          | inrush_multiplier       | -1.0    | -1 = usa perfil clase                       |
| ElectricalConsumer          | inrush_duration         | -1.0    | -1 = usa perfil clase                       |
| ElectricalConsumer          | has_switch              | false   | crea CheckButton si true                    |
| ElectricalConsumer          | is_switched_on          | true    | estado logico interruptor                   |
| ElectricalConsumer          | visual_sprite           | null    | Sprite2D a teñir                            |
| ElectricalConsumer          | visual_light            | null    | PointLight2D a modular                      |
| ElectricalConsumer          | flicker_intensity       | 0.2     | amplitud parpadeo                           |
| ElectricalBreaker           | rated_current           | 20.0    | In en amperios                              |
| ElectricalBreaker           | magnetic_curve          | 1       | 0=B, 1=C, 2=D                               |
| ElectricalBreaker           | connected_components    | []      | Array[ElectricalComponent]                  |
| VoltageRegulator            | nominal_voltage         | 220.0   |                                             |
| VoltageRegulator            | regulation_band         | 0.10    | rango 0.01-0.25                             |
| VoltageRegulator            | blackout_threshold      | 0.5     | 0 desactiva blackout                        |
| VoltageRegulator            | connected_components    | []      | Array[ElectricalComponent]                  |
| ElectricalSplitPhasePanel   | phase_1_components      | []      | Array[ElectricalComponent]                  |
| ElectricalSplitPhasePanel   | phase_2_components      | []      | Array[ElectricalComponent]                  |
| ElectricalSplitPhasePanel   | biphasic_components     | []      | Array[ElectricalComponent]                  |
| ElectricalDistributionPanel | phase_1_circuits        | []      | Array[BranchCircuit]                       |
| ElectricalDistributionPanel | phase_2_circuits        | []      | Array[BranchCircuit]                       |
| ElectricalDistributionPanel | biphasic_circuits       | []      | Array[BranchCircuit]                       |
| BranchCircuit               | circuit_name            | "Circuito" |                                         |
| BranchCircuit               | rated_current           | 20.0    | In                                          |
| BranchCircuit               | magnetic_curve          | 1       | 0=B, 1=C, 2=D                               |
| BranchCircuit               | connected_components    | []      | Array[ElectricalComponent]                  |
| Cable                       | electrical_wire         | null    | ref a ElectricalWire                        |
| Cable                       | stress_gradient         | cable_gradient.tres | Gradient resource                |

### C. Grupos de Godot definidos

| Grupo                  | Anyadido en                                | Consumido en                                                              |
|------------------------|--------------------------------------------|---------------------------------------------------------------------------|
| `power_sources`        | electrical_source.gd:22                   | main_engine.gd:59, electrical_consumer.gd:112/196, electrical_distribution_panel.gd:129/142 |
| `switchable_devices`   | electrical_consumer.gd:99 (si has_switch) | main_engine.gd:58                                                         |
| `electrical_components`| electrical_component.gd:18                | main_engine.gd:54                                                         |
| `breakers`             | electrical_breaker.gd:35                  | (reservado, sin caller)                                                   |

### D. Senales custom

| Senal                                      | Declarada en              | Emitida en              | Consumida en              |
|--------------------------------------------|---------------------------|--------------------------|----------------------------|
| `global_voltage_changed(voltage)`          | globals.gd:3              | main_engine.gd:46       | electrical_source.gd:21    |
| `sun_info_changed(hour, rotation_deg)`     | day_night_cycle.gd:3      | day_night_cycle.gd:68   | main_engine.gd:21          |

### E. Constantes fisicas y de configuracion

**`AWG_SPECS`** (electrical_wire.gd:21-25):
| Gauge | rho (ohm/m) | I_max (A) |
|-------|-------------|-----------|
| 0     | 0.00828     | 15        |
| 1     | 0.00521     | 20        |
| 2     | 0.00327     | 30        |

**`CLASS_CUTOFF`** (electrical_consumer.gd:22-28):
| Clase        | V_cutoff (fraccion) |
|--------------|---------------------|
| INCANDESCENT | 0.60                |
| MOTOR        | 0.85                |
| COMPRESSOR   | 0.85                |
| SMPS         | 0.80                |
| MIXED        | 0.80                |

**`INRUSH_PROFILES`** (electrical_consumer.gd:48-54):
| Clase        | Multiplicador | Duracion (s) |
|--------------|---------------|--------------|
| INCANDESCENT | 12.0          | 0.15         |
| MOTOR        | 6.0           | 2.0          |
| COMPRESSOR   | 6.0           | 0.5          |
| SMPS         | 2.0           | 0.1          |
| MIXED        | 2.5           | 0.5          |

**`MAGNETIC_MULTIPLIERS`** (electrical_breaker.gd:31 y branch_circuit.gd:32):
| Curva | Multiplicador |
|-------|---------------|
| B (0) | 4.0           |
| C (1) | 7.5           |
| D (2) | 15.0          |

**`THERMAL_THRESHOLD_*`** (electrical_breaker.gd:28-30 y branch_circuit.gd:29-31):
| Constante              | Valor | Tiempo de disparo |
|------------------------|-------|---------------------|
| THERMAL_THRESHOLD_1    | 1.13  | 14400 s (4 h)      |
| THERMAL_THRESHOLD_2    | 1.30  | 3600 s (1 h)       |
| THERMAL_THRESHOLD_3    | 1.45  | 600 s (10 min)     |

**`main_engine.gd:10-11`:**
| Constante       | Valor |
|-----------------|-------|
| HISTORY_SIZE    | 80    |
| SAMPLE_INTERVAL | 0.15  |

**`main_engine.tscn:119-122`:**
| Parametro VSlider  | Valor  |
|--------------------|--------|
| min_value          | 110    |
| max_value          | 280    |
| step               | 10     |
| value              | 220    |

**`electrical_distribution_panel.gd:26`:**
| Constante   | Valor | Notas                                |
|-------------|-------|--------------------------------------|
| _last_delta | 0.016 | Fallback ~60 FPS para I^2t breaker  |

### F. Glosario de terminos

- **AWG (American Wire Gauge):** sistema estandar de calibres de cable. A mayor numero AWG, menor seccion. Estandar ASTM B258.
- **AVR (Automatic Voltage Regulator):** regulador electronico de voltaje. Mantiene V_out dentro de una banda de tolerancia.
- **Breaker (disyuntor):** dispositivo de proteccion que interrumpe automaticamente el circuito frente a sobrecorriente.
- **BROKEN (estado):** estado terminal de un electrodomestico que ha superado V_burnout. No se repara solo.
- **Cos(phi) o factor de potencia:** relacion entre potencia real y potencia aparente en circuitos AC. 1.0 = resistivo puro.
- **Curva B/C/D:** clasificaciones IEC 60898 de la sensibilidad magnetica del breaker (3-5 In, 5-10 In, 10-20 In).
- **Flicker (parpadeo):** variacion rapida y visible de la luminosidad, sintoma de mal suministro electrico.
- **GFCI/RCD (Ground Fault Circuit Interrupter / Residual Current Device):** proteccion diferencial. Detecta corrientes de fuga a tierra.
- **Gauss-Seidel:** metodo iterativo para resolver sistemas de ecuaciones lineales. Converge en una iteracion para matrices triangulares inferiores.
- **IEC 60898:** norma internacional para breakers termomagneticos de instalaciones domesticas.
- **Inrush (corriente de arranque):** corriente transitoria alta al encender una carga, especialmente motores y filamentos.
- **I^2t (integral de Joules):** integral de tiempo de I^2, usada para coordinar protecciones y modelar calentamiento.
- **KCL/KVL:** leyes de Kirchhoff de corrientes y tensiones.
- **NEC (National Electrical Code):** reglamento de instalaciones electricas de EE.UU. (referencia para ampacidades y calibres AWG).
- **NORMAL (estado):** estado nominal de operacion, V_in entre 0.90 y 1.05 V_nom por defecto.
- **OFF (estado):** estado apagado, V_in por debajo del umbral de encendido. R = INF.
- **OVERVOLTAGE (estado):** V_in entre 1.05 y 1.25 V_nom. Funcionamiento posible pero con riesgo de dano.
- **Skin effect (efecto pelicular):** tendencia de la corriente AC a fluir por la superficie del conductor a alta frecuencia.
- **Split-phase:** sistema monofasico con neutro derivado, comun en Americas (120/240 V) y Argentina (220 V bifasico).
- **STRESS termico:** relacion I_actual / I_max del cable. > 1.0 indica sobrecarga.
- **Thevenin (equivalente):** modelo de una fuente real como una fuente ideal en serie con una impedancia.
- **UNDERVOLTAGE (estado):** V_in por debajo de 0.90 V_nom pero por encima del umbral de encendido. Operacion deficiente.
- **Z_source (impedancia de fuente):** impedancia Thevenin de la red electrica vista desde un punto dado.

### G. Referencias bibliograficas y normativas

- **IEC 60898-1:2015.** "Electrical accessories - Circuit-breakers for overcurrent protection for household and similar installations - Part 1: Circuit-breakers for a.c. operation."
- **ASTM B258-14.** "Standard Specification for Standard Nominal Diameters and Cross-Sectional Areas of AWG Sizes of Solid Round Wires Used as Electrical Conductors."
- **NFPA 70 (NEC) 2020.** "National Electrical Code." Tabla 8 (propiedades de conductores) y Tabla 310.15(B)(16) (ampacidades).
- **IEEE Std 141-1993 (Red Book).** "IEEE Recommended Practice for Electric Power Distribution for Industrial Plants."
- **IEEE Std 1459-2010.** "Definitions for the Measurement of Electric Power Quantities Under Sinusoidal, Nonsinusoidal, Balanced, or Unbalanced Conditions."
- **Schneider Electric.** "Electrical Installation Guide." Cap. 3 (regulacion de voltaje) y Cap. 4 (protecciones).
- **GODOT Documentation.** "SceneTree Groups," "CanvasLayer," "Signals," [https://docs.godotengine.org/](https://docs.godotengine.org/).
- **Nilsson & Riedel.** "Electric Circuits." 11th ed. Pearson, 2018. (Texto introductorio de referencia para ley de Ohm, Kirchhoff, Thevenin.)

### H. Indice cruzado termino -> codigo

| Termino                        | Implementacion                                              |
|--------------------------------|--------------------------------------------------------------|
| Ley de Ohm                     | electrical_consumer.gd:293-297                              |
| Potencia                       | electrical_consumer.gd:271-274                              |
| Resistencia interna consumidor | electrical_consumer.gd:82-87                                |
| Thevenin                       | electrical_source.gd:32-54                                  |
| AWG                            | electrical_wire.gd:21-25                                    |
| Cada de tension en cable       | electrical_wire.gd:51-66                                    |
| Estres termico                 | electrical_wire.gd:51-66                                    |
| Estado OFF                     | electrical_consumer.gd:163                                  |
| Estado UNDERVOLTAGE            | electrical_consumer.gd:158-160                              |
| Estado NORMAL                  | electrical_consumer.gd:155-157                              |
| Estado OVERVOLTAGE             | electrical_consumer.gd:151-153                              |
| Estado BROKEN                  | electrical_consumer.gd:144-147                              |
| Inrush INCANDESCENT            | electrical_consumer.gd:48-54, 168-196                       |
| Inrush MOTOR                   | electrical_consumer.gd:48-54, 168-196                       |
| Breaker magnetico B            | electrical_breaker.gd:31, 62-77                             |
| Breaker magnetico C            | electrical_breaker.gd:31, 62-77                             |
| Breaker magnetico D            | electrical_breaker.gd:31, 62-77                             |
| Breaker termico I^2t           | electrical_breaker.gd:28-30, 64-89                          |
| AVR clipping                   | voltage_regulator.gd:40-69                                  |
| AVR blackout                   | voltage_regulator.gd:40-69                                  |
| Split-phase 220V               | electrical_split_phase_panel.gd:19-59                       |
| Corriente de neutro            | electrical_split_phase_panel.gd:53, electrical_distribution_panel.gd:87 |
| Branch circuit                 | branch_circuit.gd:37-50                                     |
| Inicializacion debug UI        | electrical_component.gd:21-55                               |
| Top_level Line2D               | common_cable.tscn:13                                        |
| Mouse filter ignore            | main_engine.tscn (multiples lineas), pedagogical_overlay.gd:50 |
| super._ready()                 | electrical_source.gd:19, electrical_wire.gd:28, electrical_consumer.gd:80, electrical_breaker.gd:34, voltage_regulator.gd:37, electrical_distribution_panel.gd:29 |
| VSlider 110-280                | main_engine.tscn:119-122                                    |
| Chart de voltaje               | main_engine.gd:90-125                                       |
| Boost nocturno                 | electrical_consumer.gd:228                                  |
| Disclaimer modelo              | pedagogical_overlay.gd:11-24                               |
| Tecla H                        | pedagogical_overlay.gd:9, 80-84                             |
| Reset escena                   | main_engine.gd:49                                           |

---

**FIN DEL DOCUMENTO**

Version: 1.0
Autor del documento: Generado a partir del analisis estatico del codigo fuente del proyecto EMS.
Fecha: 2026
Licencia: Misma que el proyecto (ver archivo LICENSE si existe).
