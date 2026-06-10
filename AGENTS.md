# AGENTS.md - Simulador Eléctrico (EMS) en Godot

## 1. Visión General del Proyecto
Este proyecto es un simulador de circuitos y gestión eléctrica (Electrical Management System) desarrollado en **Godot Engine 4.x** usando **GDScript**. 
El objetivo es simular en tiempo real el comportamiento de una red eléctrica doméstica, calculando la carga, el estrés térmico en los cables, caídas de tensión y el estado de los electrodomésticos según las variaciones de voltaje.

**Tono del Proyecto:** Simulación técnica y educativa con fuerte énfasis en el "Game Feel" (retroalimentación visual a través de colores y vibraciones de pantalla/nodos).

---

## 2. Objetivos Específicos del Proyecto

1. **Análisis de Parámetros Eléctricos:** Analizar los parámetros de consumo residencial, la tolerancia de los equipos y la capacidad de conducción según el calibre del cableado.
2. **Modelado Matemático con Variable Estocástica:** Programar en GDScript los algoritmos matemáticos que modelan la tensión y estrés de dispositivos electrónicos mediante variables estocásticas.
3. **Interfaz Gráfica Interactiva:** Modelar una interfaz gráfica interactiva en Godot Engine para visualizar en tiempo real la carga de los circuitos y las alertas de sobrecalentamiento.
4. **Validación de Dispositivos de Protección:** Validar mediante el simulador la efectividad de implementar dispositivos de protección virtual como reguladores de voltaje, protectores de picos y sistemas UPS.

---

## 3. Arquitectura de Nodos y Filosofía de Diseño (ya existente)

El proyecto sigue una estricta **Separación de Preocupaciones (Separation of Concerns)** entre la lógica matemática y la representación visual.

* **Lógica Matemática:** Nodos invisibles (ej. `Node2D` básicos) que realizan los cálculos de las leyes de Kirchhoff y Ohm.
* **Representación Visual:** Nodos como `Line2D` o `Sprite2D` que leen las variables lógicas y reaccionan a ellas.
* **Composición visual:** Los textos de depuración flotantes (`debug_label`) se instancian por código en la clase base para mantener el editor limpio.

### Coordenadas y Posicionamiento
* Los cables visuales (`Cable` / `Line2D`) usan `top_level = true` para independizarse de las transformaciones de sus padres. Esto evita el "doble desplazamiento" si se agrupan en nodos organizadores.
* Los nodos lógicos (`ElectricalWire`) se pueden mover libremente en el editor 2D. Su posición determina dónde se dibujará la etiqueta de depuración.

---

## 4. Físicas y Matemáticas Centrales

El motor de simulación se basa en cálculos reales de circuitos de corriente continua/alterna simplificada. 

* **Ley de Ohm:** La corriente absorbida por un dispositivo se calcula mediante la fórmula $I = \frac{V}{R}$.
* **Potencia Eléctrica:** El consumo se muestra en Watts usando $P = V \cdot I$.
* **Resistencia Dinámica:** * Un dispositivo en estado óptimo calcula su resistencia interna basándose en sus valores nominales: $R = \frac{V_{nom}^2}{P_{nom}}$.
    * Si un dispositivo está apagado (OFF) o quemado (BROKEN), simulamos un circuito abierto asignando una resistencia infinita: $R = \infty$ (en GDScript: `INF`), lo que fuerza la corriente a 0 A.
* **Estrés Térmico (Cables):** Se calcula como una relación entre el flujo actual y el límite físico del cable: $\text{Estrés} = \frac{I_{actual}}{I_{max}}$. Valores $> 1.0$ provocan sobrecarga visual (temblor y enrojecimiento).
* **Corriente de Irrupción (Inrush Current):** Modelo de decaimiento exponencial que simula el pico de corriente al encender un dispositivo:
    * Fórmula: $I(t) = I_{nom} \times (k \cdot e^{-\frac{t}{\tau}} + 1)$
    * $k$: Multiplicador extra del pico (pico total = $k+1$ veces la nominal).
    * $\tau$ (tau): Constante de tiempo que define la velocidad de decaimiento.
    * Perfiles por clase de dispositivo en `INRUSH_PROFILES` (SMPS: k=29/τ=0.015s, Incandescente: k=11/τ=0.04s, Motor: k=6/τ=0.25s, Compresor: k=5/τ=0.8s, Mixto: k=1.5/τ=0.1s).
    * Optimización: El efecto se corta cuando $t > 5\tau$ (multiplicador ≈ 1.006, despreciable).

---

## 5. Clases Principales y Jerarquía

### `ElectricalComponent` (Clase Base)
* **Hereda de:** `Node2D`
* **Propiedades:** `voltage_in`, `current_draw`, `equivalent_resistance`.
* **Responsabilidad:** Propagar voltajes, instanciar el `Label` de depuración (`debug_label`), y proveer la base de texto virtual `get_debug_text()`.

### `ElectricalConsumer` (Electrodomésticos)
* **Hereda de:** `ElectricalComponent`
* **Responsabilidad:** Controlar la lógica de consumo y los estados visuales del `Sprite2D` asociado.
* **Estados (Enum `DeviceState`):**
    * `OFF`: Tinte gris, $R = \infty$. Voltaje por debajo del umbral de encendido.
    * `UNDERVOLTAGE`: Tinte amarillento. Voltaje insuficiente pero superior al corte.
    * `NORMAL`: Tinte blanco (original).
    * `OVERVOLTAGE`: Tinte naranja + vibración leve. Estrés térmico previo a la ruptura.
    * `BROKEN`: Tinte rojo + vibración violenta, $R = \infty$. Ocurre al superar el límite crítico de fábrica.
* **Control:** Soporta interruptores individuales (`CheckButton`) generados por código si `has_switch == true`.

### `ElectricalWire` (Lógica de Cable)
* **Hereda de:** `ElectricalComponent`
* **Responsabilidad:** Calcular la caída de voltaje y el estrés térmico basado en su calibre (AWG) y longitud en metros.
* **Nota:** Se posiciona manualmente en el editor para ubicar la lectura de datos sin superponerse a las líneas.

### `Cable` (Visualización de Cable)
* **Hereda de:** `Line2D`
* **Responsabilidad:** Leer el `thermal_stress` del `ElectricalWire` enlazado. Si supera 1.0, cambia el gradiente de color a rojo y aplica un `shake_intensity` usando su `global_position` original.

### `ElectricalSource` (Regulador/Tablero)
* **Hereda de:** `Node2D`
* **Responsabilidad:** Es el nodo raíz del árbol eléctrico. Inicia los pulsos de cálculo (`update_network`) hacia sus hijos conectados.

### `UninterruptiblePowerSupply` (UPS)
* **Hereda de:** `ElectricalComponent`
* **Responsabilidad:** Proporcionar respaldo energético mediante batería durante apagones. Modela un UPS residencial básico con transferencia automática.
* **Jerarquía en la red:** `ElectricalSource → VoltageRegulator → UPS → ElectricalDistributionPanel`
* **Modos de operación:**
    * `NORMAL`: Red estable, pasa voltaje directamente. Carga batería si < 100%.
    * `CHARGING`: Red estable pero batería < 100%, mostrando progreso de carga.
    * `BATTERY`: Red caída, UPS activa batería e inversor para mantener cargas.
    * `LOW_BATTERY`: Batería < 20%, aviso de apagón inminente.
    * `OVERLOAD`: Carga excede capacidad máxima del UPS (1500VA).
    * `OFF`: Sin batería disponible, apagado total.
* **Parámetros clave:**
    * `battery_capacity_wh`: Capacidad en Wh (típico: 1500Wh para residencial).
    * `max_output_power`: Potencia máxima de salida en VA.
    * `blackout_threshold`: Umbral de voltaje para activar batería (0.85 = 85%).
    * `reconnect_voltage`: Voltaje mínimo para volver a red (190V).
* **Demo de apagón:** Botón "Simular Apagón (5s)" en UI fuerza voltaje a 0 por 5 segundos para validar protección.

---

## 6. Sistema de Comunicación (Señales y Grupos)

Para evitar referencias cruzadas (Spaghetti Code), el simulador usa los "Grupos" de Godot (SceneTree Groups) para comunicaciones ascendentes o globales:

* **Grupo `power_sources`:** Contiene los reguladores principales. Cuando un usuario acciona un interruptor local, el dispositivo llama a `get_tree().call_group("power_sources", "update_network")` para forzar un recálculo total e instantáneo de la red.
* **Grupo `switchable_devices`:** Contiene todos los `ElectricalConsumer` que tienen `has_switch = true`. Usado por la Interfaz de Usuario (UI) para encender/apagar toda la casa a la vez.

---

## 7. Reglas de Desarrollo y Prevención de Errores Comunes (Godot Quirks)

Si un Agente (IA) o desarrollador humano va a modificar este código, DEBE seguir estas reglas:

1.  **Herencia de Funciones Visuales:** Al sobrescribir funciones base como `_ready()` o `_process()` en nodos hijos (ej. `ElectricalConsumer`), **SIEMPRE** llamar primero a `super._ready()` o `super._process(delta)`. De lo contrario, los textos flotantes base se romperán.
2.  **Manejo de Interfaces (UI Shielding):** Cualquier panel global o `CanvasLayer` que actúe como fondo o contenedor debe tener la propiedad **Mouse -> Filter** puesta en `Ignore`. Si se deja en `Stop`, bloqueará los clics a los interruptores (`CheckButton`) instanciados en el mundo 2D.
3.  **Trazado de Cables:** Los `Line2D` (Cables) jamás deben moverse arrastrando el centro del nodo. Su propiedad Transform -> Position debe permanecer en `(0,0)`. Para mover las líneas, se editan sus **puntos locales**, y luego se bloquea el nodo en el editor (ícono de candado).
4.  **Cero Divisiones Matemáticas:** Al restaurar un electrodoméstico desde un estado apagado, siempre restablecer `equivalent_resistance = internal_resistance` *antes* de calcular $I = \frac{V}{R}$ para evitar bugs de persistencia de $0.0$ amperios.