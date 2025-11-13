#!/bin/bash
# === ЦВЕТА ===
RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; MAGENTA='\e[35m'; CYAN='\e[36m'; RESET='\e[0m'
cecho() { echo -e "${2}${1}${RESET}"; }
# === СТОП-СЛОВА ===
declare -A STOPWORDS
STOPWORDS_FILE="$HOME/.bash_stopwords.txt"
if [[ -f "$STOPWORDS_FILE" ]]; then
    while IFS= read -r word || [[ -n "$word" ]]; do
        [[ -n "$word" && "$word" =~ ^[a-zA-Z]+$ ]] && STOPWORDS["$word"]=1
    done < "$STOPWORDS_FILE"
else
    for w in the and or but to of a an in on at for with from by is was are were this that; do
        STOPWORDS["$w"]=1
    done
fi
# ==============================================================================
# ОБЩИЕ ФУНКЦИИ И ПЕРЕМЕННЫЕ
# ==============================================================================
error_exit() { cecho "ОШИБКА: $1" "$RED" >&2; exit 1; }
# ==============================================================================
# ЗАДАНИЕ 1: ШАХМАТНАЯ ДОСКА (Функция)
# ==============================================================================
draw_chessboard() {
    local size="$1"
    [[ "$size" =~ ^[1-9][0-9]*$ ]] || error_exit "Размер должен быть числом ≥1"
    echo "Рисуем доску ${size}x${size} ..."
    local c1='\e[48;5;236m \e[0m'
    local c2='\e[48;5;255m \e[0m'
    for ((i=0; i<size; i++)); do
        for ((j=0; j<size; j++)); do
            (( (i+j) % 2 == 0 )) && echo -en "$c1" || echo -en "$c2"
        done
        echo
    done
}
# ==============================================================================
# ЗАДАНИЕ 2: АНАЛОГ du (Функции)
# ==============================================================================
format_size_simple() {
    local bytes="$1"
    local kb=1024
    local mb=$((kb * 1024))
    local gb=$((mb * 1024))

    if (( bytes == 0 )); then
        echo "0B"
        return
    fi

    if (( bytes >= gb )); then
        echo "$((bytes / gb))G"
    elif (( bytes >= mb )); then
        echo "$((bytes / mb))M"
    elif (( bytes >= kb )); then
        echo "$((bytes / kb))K"
    else
        echo "${bytes}B"
    fi
}
calculate_sizes_recursive() {
    local dir_path="$1" total_size=0
    if find "$dir_path" -maxdepth 0 -printf "%s" >/dev/null 2>&1; then
        mapfile -t sizes < <(find "$dir_path" -type f -printf "%s\n" 2>/dev/null)
        for s in "${sizes[@]}"; do ((total_size += s)); done
        while IFS= read -r -d '' subdir; do
            [[ -d "$subdir" ]] && total_size=$((total_size + $(calculate_sizes_recursive "$subdir")))
        done < <(find "$dir_path" -maxdepth 1 -mindepth 1 -type d -print0)
    else
        while IFS= read -r -d '' entry; do
            if [[ -f "$entry" ]] && [[ ! -L "$entry" ]]; then
                s=$(stat -c %s "$entry" 2>/dev/null || echo 0)
                ((total_size += s))
            elif [[ -d "$entry" ]] && [[ ! -L "$entry" ]]; then
                ((total_size += $(calculate_sizes_recursive "$entry")))
            fi
        done < <(find "$dir_path" -maxdepth 1 -mindepth 1 -print0)
    fi
    echo "$total_size"
}
run_du_analog() {
    local dir="${1%/}"
    [[ -d "$dir" ]] || error_exit "Директория '$dir' не найдена."
    [[ -r "$dir" && -x "$dir" ]] || error_exit "Нет прав на чтение или вход в '$dir'."
    echo "Подсчет размеров в '$dir'..."
    local total=$(calculate_sizes_recursive "$dir")
    local formatted=$(format_size_simple "$total")
    cecho "$dir: $formatted" "$GREEN"
}
# ==============================================================================
# ЗАДАНИЕ 3: СОРТИРОВКА ФАЙЛОВ ПО РАСШИРЕНИЯМ (Функция)
# ==============================================================================
sort_files_by_extension() {
  local target_dir="$1"
  target_dir="${target_dir%/}"
  if [ ! -d "$target_dir" ]; then
    error_exit "Директория '$target_dir' не найдена."
  fi
  if [ ! -r "$target_dir" ] || [ ! -w "$target_dir" ] || [ ! -x "$target_dir" ]; then
    error_exit "Нет прав на чтение/запись/вход в директорию '$target_dir'."
  fi
  echo "Сортировка файлов в '$target_dir' по расширениям..."
  find "$target_dir" -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' file_path; do
    local filename
    filename=$(basename "$file_path")
    local extension="${filename##*.}"
    local subdir_name
    if [[ "$filename" == "$extension" ]] || [[ "$filename" == .* && "${filename#.*}" == "" ]]; then
        subdir_name="no_extension"
    else
        subdir_name="${extension,,}"
    fi
    local dest_dir="$target_dir/$subdir_name"
    mkdir -p "$dest_dir"
    if [ $? -ne 0 ]; then
        echo "Предупреждение: Не удалось создать папку '$dest_dir'. Пропуск файла '$filename'." >&2
        continue
    fi
    echo "Перемещение: '$filename' -> '$subdir_name/'"
    mv -f "$file_path" "$dest_dir/"
    if [ $? -ne 0 ]; then
        echo "Предупреждение: Не удалось переместить '$filename' в '$dest_dir'." >&2
    fi
  done
  echo "Сортировка завершена."
}
# ==============================================================================
# ЗАДАНИЕ 4: РЕЗЕРВНОЕ КОПИРОВАНИЕ С РОТАЦИЕЙ (Функция)
# ==============================================================================
create_backup_with_rotation() {
  local source_dir="$1"
  local backup_dir="$2"
  source_dir="${source_dir%/}"
  backup_dir="${backup_dir%/}"
  local days_to_keep=7
  # Проверка на совпадение путей
  if [ "$source_dir" = "$backup_dir" ]; then
    error_exit "Исходная директория и директория для бэкапов не могут совпадать."
  fi
  # Проверка что backup_dir не находится внутри source_dir
  if [[ "$backup_dir" == "$source_dir"/* ]]; then
    error_exit "Директория для бэкапов не может находиться внутри исходной директории."
  fi
  if [ ! -d "$source_dir" ]; then
    error_exit "Исходная директория '$source_dir' не найдена."
  fi
  if [ ! -r "$source_dir" ] || [ ! -x "$source_dir" ]; then
    error_exit "Нет прав на чтение или вход в исходную директорию '$source_dir'."
  fi
  if [ ! -d "$backup_dir" ]; then
    echo "Инфо: Создаю директорию для бэкапов '$backup_dir'..."
    mkdir -p "$backup_dir" || error_exit "Не удалось создать директорию '$backup_dir'."
  fi
  if [ ! -w "$backup_dir" ] || [ ! -x "$backup_dir" ]; then
    error_exit "Нет прав на запись или вход в директорию для бэкапов '$backup_dir'."
  fi
  local datestamp
  datestamp=$(date +%Y-%m-%d_%H%M%S)
  local source_basename
  source_basename=$(basename "$source_dir")
  local archive_name="${source_basename}_${datestamp}.tar.gz"
  local archive_path="$backup_dir/$archive_name"
  local source_parent_dir
  source_parent_dir=$(dirname "$source_dir")
  echo "Создание бэкапа '$source_dir' в '$archive_path'..."
  tar -czf "$archive_path" -C "$source_parent_dir" "$source_basename"
  if [ $? -eq 0 ]; then
    echo "Бэкап успешно создан: '$archive_name'"
  else
    rm -f "$archive_path"
    error_exit "Не удалось создать бэкап."
  fi
  echo "Удаление старых бэкапов (старше $days_to_keep дней) в '$backup_dir'..."
  find "$backup_dir" -name "${source_basename}_*.tar.gz" -type f -mtime "+$((days_to_keep - 1))" -print -delete
  if [ $? -ne 0 ]; then
    echo "Предупреждение: Возникли ошибки при поиске или удалении старых бэкапов." >&2
  fi
  echo "Резервное копирование и ротация завершены."
}
# ==============================================================================
# ЗАДАНИЕ 5: АНАЛИЗ ЧАСТОТЫ СЛОВ (Функция)
# ==============================================================================
# ==============================================================================
# ЗАДАНИЕ 5: АНАЛИЗ ЧАСТОТЫ СЛОВ (ИСПРАВЛЕНО + КРАСИВЫЕ СООБЩЕНИЯ)
# ==============================================================================
analyze_word_frequency() {
  local search_dir="$1"
  local extension="$2"
  local top_n="$3"
  search_dir="${search_dir%/}"

  if [ ! -d "$search_dir" ]; then
    error_exit "Ошибка: '$search_dir' не является директорией или не существует."
  fi
  if ! [[ "$top_n" =~ ^[0-9]+$ ]] || [ "$top_n" -le 0 ]; then
    error_exit "Ошибка: Топ-N должен быть положительным числом."
  fi
  if [ ! -r "$search_dir" ] || [ ! -x "$search_dir" ]; then
    error_exit "Нет прав на чтение или вход в директорию '$search_dir'."
  fi

  echo "Анализ частоты слов для *.$extension в '$search_dir' (Топ-$top_n)..."

  local files
  mapfile -d '' files < <(find "$search_dir" -type f -name "*.$extension" -print0 2>/dev/null)

  if [ ${#files[@]} -eq 0 ]; then
    error_exit "В директории '$search_dir' нет файлов с расширением '.$extension'"
  fi

  local STOPWORDS_FILE="stopwords.txt"
  local STOPWORDS_REGEX=""
  if [ -f "$STOPWORDS_FILE" ]; then
    STOPWORDS_REGEX=$(cat "$STOPWORDS_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]' | grep -v '^$' | tr '\n' '|' | sed 's/|$//')
    if [ -n "$STOPWORDS_REGEX" ]; then
      echo "Инфо: Загружено стоп-слов из '$STOPWORDS_FILE'"
    fi
  else
    echo "Предупреждение: Файл стоп-слов '$STOPWORDS_FILE' не найден — стоп-слова не будут исключены."
  fi

  declare -A WORD_COUNT
  local WORD_FOUND=0

  for file in "${files[@]}"; do
    local words
    words=$(tr '[:upper:]' '[:lower:]' < "$file" 2>/dev/null | tr -d '[:punct:]' | grep -ohE '\w+')
    while read -r word; do
      [[ -z "$word" ]] && continue
      WORD_FOUND=1
      if [ -n "$STOPWORDS_REGEX" ] && [[ "$word" =~ ^($STOPWORDS_REGEX)$ ]]; then
        continue
      fi
      ((WORD_COUNT["$word"]++))
    done <<< "$words"
  done

  if [ $WORD_FOUND -eq 0 ]; then
    error_exit "В файлах с расширением '.$extension' не найдено ни одного слова."
  fi

  echo "--- Топ-$top_n самых частых слов ---"
  for word in "${!WORD_COUNT[@]}"; do
    printf '%s: %d\n' "$word" "${WORD_COUNT[$word]}"
  done | sort -t: -k2 -nr | head -n "$top_n"
  echo "---------------------------------"

  unset WORD_COUNT
  return 0
}
# ==============================================================================
# ГЛАВНАЯ ЧАСТЬ СКРИПТА: МЕНЮ И ЗАПУСК ЗАДАЧ
# ==============================================================================
echo "-----------------------------------------"
echo "Доступные задачи:"
echo " 1. Шахматная доска"
echo " 2. Аналог 'du' (размер директорий)"
echo " 3. Сортировка файлов по расширениям"
echo " 4. Резервное копирование с ротацией"
echo " 5. Анализ частоты слов"
echo " 0. Выход"
echo "-----------------------------------------"
read -p "Введите номер задачи (1-5) или 0 для выхода: " task_choice
case "$task_choice" in
  1)
    echo "--- Задача 1: Шахматная доска ---"
    read -p "Введите размер доски (например, 8): " board_size
    if ! [[ "$board_size" =~ ^[1-9][0-9]*$ ]]; then
      error_exit "Неверный ввод. Размер должен быть положительным числом."
    fi
   draw_chessboard "$board_size"
    ;;
  2)
    echo "--- Задача 2: Аналог 'du' ---"
    read -e -p "Введите путь к директории для анализа: " du_dir
    if [ -z "$du_dir" ]; then
      error_exit "Путь к директории не может быть пустым."
    fi
    run_du_analog "$du_dir"
    ;;
  3)
    echo "--- Задача 3: Сортировка файлов ---"
    read -e -p "Введите путь к директории для сортировки файлов: " sort_dir
    if [ -z "$sort_dir" ]; then
      error_exit "Путь к директории не может быть пустым."
    fi
    sort_files_by_extension "$sort_dir"
    ;;
  4)
    echo "--- Задача 4: Резервное копирование ---"
    read -e -p "Введите путь к ИСХОДНОЙ директории для бэкапа: " backup_source
    read -e -p "Введите путь к директории для СОХРАНЕНИЯ бэкапов: " backup_dest
    if [ -z "$backup_source" ] || [ -z "$backup_dest" ]; then
      error_exit "Пути к директориям не могут быть пустыми."
    fi
    create_backup_with_rotation "$backup_source" "$backup_dest"
    ;;
  5)
    echo "--- Задача 5: Анализ частоты слов ---"
    read -e -p "Введите путь к директории для поиска файлов: " stats_dir
    read -p "Введите расширение файлов (например, txt или log): " stats_ext
    read -p "Введите количество топ-слов для вывода (N): " stats_top_n
    if [ -z "$stats_dir" ] || [ -z "$stats_ext" ]; then
      error_exit "Путь к директории и расширение не могут быть пустыми."
    fi
    if ! [[ "$stats_top_n" =~ ^[1-9][0-9]*$ ]]; then
      error_exit "Количество топ-слов (N) должно быть положительным числом."
    fi
    analyze_word_frequency "$stats_dir" "$stats_ext" "$stats_top_n"
    ;;
  0)
    echo "Выход."
    exit 0
    ;;
  *)
    error_exit "Неверный выбор '$task_choice'. Запустите скрипт заново."
    ;;
esac
exit 0