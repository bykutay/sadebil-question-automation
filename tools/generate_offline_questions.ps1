param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [int]$PerCategory = 1500,
    [string]$AssetDir = ""
)

$ErrorActionPreference = "Stop"

function New-Topic($term, $answer, $fact) {
    [PSCustomObject]@{
        term   = $term
        answer = $answer
        fact   = $fact
    }
}

function Parse-Topics([string[]]$rows) {
    $topics = @()
    foreach ($row in $rows) {
        $parts = $row -split "\|", 3
        if ($parts.Count -ne 3) {
            throw "Konu satırı hatalı: $row"
        }
        $topics += New-Topic $parts[0] $parts[1] $parts[2]
    }
    return $topics
}

function Parse-TopicPairs([string[]]$rows, $categoryName) {
    $topics = @()
    foreach ($row in $rows) {
        $parts = $row -split "\|", 2
        if ($parts.Count -ne 2) {
            throw "Ek konu satırı hatalı: $row"
        }
        $term = $parts[0]
        $answer = $parts[1]
        $fact = switch ($categoryName) {
            "ekonomi" { "$term, ekonomide $answer anlatan bir kavramdır." }
            "bilim" { "$term, bilimde $answer açıklayan bir kavramdır." }
            "teknoloji" { "$term, teknolojide $answer anlatan bir kavramdır." }
            "sanat" { "$term, sanatta $answer anlatan bir kavramdır." }
            "muzik" { "$term, müzikte $answer anlatan bir kavramdır." }
            "tarih" { "$term, tarihte $answer anlatan bir kavramdır." }
            "guncel" { "$term, güncel yaşamda $answer anlatan bir kavramdır." }
            default { "$term, $answer anlamıyla kullanılır." }
        }
        $topics += New-Topic $term $answer $fact
    }
    return $topics
}

function Pick-Wrongs($wrongBank, $correct, $offset) {
    $picked = @()
    $i = $offset
    while ($picked.Count -lt 3) {
        $candidate = $wrongBank[$i % $wrongBank.Count]
        if ($candidate -ne $correct -and ($picked -notcontains $candidate)) {
            $picked += $candidate
        }
        $i++
        if ($i -gt ($offset + $wrongBank.Count + 8)) {
            throw "Yeterli yanlış seçenek bulunamadı: $correct"
        }
    }
    return $picked
}

function Start-WithCapital($text, $lang) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }
    $culture = if ($lang -eq "tr") {
        [System.Globalization.CultureInfo]::GetCultureInfo("tr-TR")
    } else {
        [System.Globalization.CultureInfo]::InvariantCulture
    }
    return $text.Substring(0, 1).ToUpper($culture) + $text.Substring(1)
}

function Convert-ToNominativeTr($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }
    $words = @($text.Trim() -split "\s+")
    $last = $words[$words.Count - 1]
    if ($last -match "mayı$") { $last = $last.Substring(0, $last.Length - 4) + "ma" }
    elseif ($last -match "meyi$") { $last = $last.Substring(0, $last.Length - 4) + "me" }
    elseif ($last -match "lığı$") { $last = $last.Substring(0, $last.Length - 4) + "lık" }
    elseif ($last -match "liği$") { $last = $last.Substring(0, $last.Length - 4) + "lik" }
    elseif ($last -match "luğu$") { $last = $last.Substring(0, $last.Length - 4) + "luk" }
    elseif ($last -match "lüğü$") { $last = $last.Substring(0, $last.Length - 4) + "lük" }
    elseif ($last -match "(ını|ini|unu|ünü)$") { $last = $last.Substring(0, $last.Length - 2) }
    elseif ($last -match "(nı|ni|nu|nü)$") { $last = $last.Substring(0, $last.Length - 1) }
    elseif ($last -match "(yı|yi|yu|yü)$") { $last = $last.Substring(0, $last.Length - 2) }
    elseif ($last -match "(ışı|işi|uşu|üşü)$") { $last = $last.Substring(0, $last.Length - 1) }
    elseif ($last -match "([bcçdfgğhjklmnprsştvyz])ı$") { $last = $last.Substring(0, $last.Length - 1) }
    elseif ($last -match "([bcçdfgğhjklmnprsştvyz])i$") { $last = $last.Substring(0, $last.Length - 1) }
    elseif ($last -match "([bcçdfgğhjklmnprsştvyz])u$") { $last = $last.Substring(0, $last.Length - 1) }
    elseif ($last -match "([bcçdfgğhjklmnprsştvyz])ü$") { $last = $last.Substring(0, $last.Length - 1) }
    $words[$words.Count - 1] = $last
    return ($words -join " ")
}

function Use-NominativeAnswer($question, $lang) {
    if ($lang -ne "tr") { return $false }
    return $question -match "nedir\?|ne demektir\?|ne anlama gelir\?|hangi anlama gelir\?|akla ne gelir\?|ne anlaşılır\?|neyin adıdır\?|hangisidir\?|ne olarak adlandırılır\?|doğru tanım|hangi kısa tanım|hangi tanıma|kısa tanımı|tanımı nedir|anlamı nedir|karşılığı nedir|hangi kavramla açıklanır|hangi açıklamayla anlatılır|neyle ilgilidir|nasıl tanımlanır|nasıl açıklanır|nasıl anlatılır|neye denir|hangi anlamı taşır|sözlük anlamı|kavramsal anlamı|özet tanımı|yalın tanımı|hangi tanım|hangi açıklama|hangi ifade|hangi bilgi|hangi karşılık|hangisini anlatır|hangi seçenekte"
}

function New-QuestionText($baseQuestion, $lang, $variantIndex) {
    $question = $baseQuestion.Trim()
    if ($lang -eq "tr" -and $question.Length -lt 10 -and $question.EndsWith(" nedir?")) {
        return $question.Substring(0, $question.Length - 7) + " terimi nedir?"
    }
    return $question
}

function Test-DateQuestionText($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if ($text -match "(?i)ne\s+zaman\s+ve\s+nasıl") { return $false }
    return $text -match "(?i)(hangi\s+yıl|hangi\s+yılda|hangi\s+tarihte|kaç\s+yılında|ne\s+zaman|yılla\s+anılır|yılla\s+bilinir|in\s+which\s+year|what\s+year|which\s+year)"
}

function Test-DateAnswerText($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    $value = "$text".Trim()
    if ($value -match "^(MÖ\s*)?\d{1,4}$") { return $true }
    if ($value -match "^\d{1,2}\s+[A-Za-zÇĞİÖŞÜçğıöşü]+\s+\d{3,4}$") { return $true }
    return $false
}

function Test-NumberQuestionText($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    return $text -match "(?i)(\bkaç\b|how\s+many|how\s+much)"
}

function Test-NumberAnswerText($text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    $value = "$text".Trim()
    if ($value -match "^\d+'y?[ae]\s+\d+$") { return $true }
    return $value -match "^\d+([.,]\d+)?(\s*(derece|cm|metre|km|kg|saat|gün|ay|yıl|puan|kişi|oyuncu|halka))?$"
}

function Assert-QuestionAnswerTypes($question, $answers, $context) {
    if (Test-DateQuestionText $question) {
        foreach ($answer in $answers) {
            if (-not (Test-DateAnswerText $answer)) {
                throw "$context tarih/yıl sorusunda metin şık var: $question => $answer"
            }
        }
    } elseif (Test-NumberQuestionText $question) {
        foreach ($answer in $answers) {
            if (-not (Test-NumberAnswerText $answer)) {
                throw "$context sayı sorusunda sayısal olmayan şık var: $question => $answer"
            }
        }
    }
}

function Test-ActionAnswerText($answer) {
    if ([string]::IsNullOrWhiteSpace($answer)) { return $false }
    return "$answer" -match "(?i)(mak|mek|ma|me|mayı|meyi|meyi|etmek|yapmak|sağlamak|korumak|dinlemek|yazmak|okumak|bağlanmak|saklamak|ölçmek|izlemek|göndermek|almak|vermek|açmak|kapatmak|kullanmak|düzeltmek|yönetmek|taşımak|paylaşmak|vurmak|atmak|koşmak)$"
}

function Test-MotionAnswerText($answer) {
    if ([string]::IsNullOrWhiteSpace($answer)) { return $false }
    return "$answer" -match "(?i)(vuruş|atış|yumruk|adım|duruş|hareket|koşu|tekme|hamle|stil|teknik|sıçrama|kaldırış)"
}

function Test-QuestionAnswerMismatch($question, $correctAnswer, $answers, $lang) {
    if ($lang -ne "tr") { return $false }
    if ([string]::IsNullOrWhiteSpace($question) -or [string]::IsNullOrWhiteSpace($correctAnswer)) { return $true }
    $q = "$question"

    if ($q -match "(?i)(ne için kullanılır|ne işe yarar|ne amaçla kullanılır|hangi amaçla kullanılır)") {
        foreach ($answer in $answers) {
            if (-not (Test-ActionAnswerText $answer)) { return $true }
        }
    }

    if ($q -match "(?i)(hangi hareketi|hangi vuruşu|hangi atışı)") {
        foreach ($answer in $answers) {
            if (-not (Test-MotionAnswerText $answer)) { return $true }
        }
    }

    if ($q -match "(?i)(hangi oyun durumunu|hangi spor durumunu|hangi maç durumudur|hangi antrenman konusudur)") {
        return $true
    }

    return $false
}

function Get-DefinitionTemplates($lang) {
    if ($lang -eq "tr") {
        $subjects = @(
            "Bu soru", "Bu kısa bilgi", "Bu tanım", "Bu ifade"
        )
        $predicates = @(
            "hangi kavramı anlatır?",
            "hangi terimi açıklar?",
            "hangi kavramla ilgilidir?",
            "hangi doğru cevapla eşleşir?"
        )
    } else {
        $subjects = @(
            "This fact", "This explanation", "This definition", "This clue", "This sentence",
            "The given note", "The statement above", "This short note", "This description", "This example"
        )
        $predicates = @(
            "matches which option?",
            "describes which concept?",
            "belongs to which heading?",
            "points to which term?",
            "requires which answer?",
            "leads to which correct answer?",
            "is true for which option?",
            "signals which topic?",
            "explains which expression?",
            "is the heading of which idea?",
            "is known by which name?",
            "defines which option?",
            "is completed by which answer?",
            "is used for which concept?",
            "fits which option best?",
            "relates to which concept?",
            "supports which heading?",
            "helps find which option?",
            "points to which short answer?",
            "suggests which term?"
        )
    }
    $out = @()
    foreach ($subject in $subjects) {
        foreach ($predicate in $predicates) {
            $out += "$subject $predicate"
        }
    }
    return $out
}

function New-DefinitionClue($topic, $lang) {
    $term = [Regex]::Escape($topic.term)
    $fact = $topic.fact.Trim()
    $fact = $fact.TrimEnd(".")
    if ($lang -eq "tr") {
        $fact = [Regex]::Replace($fact, "^$term\s*,?\s*", "", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $fact = [Regex]::Replace($fact, "\b$term(la|le|yla|yle|ı|i|u|ü|yı|yi|yu|yü|da|de|ta|te|dan|den|tan|ten)?\b\s*,?\s*", "", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $fact = [Regex]::Replace($fact, "(ması|mesi|mayı|meyi)(dır|dir|dur|dür|tır|tir|tur|tür)$", '$1', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $fact = [Regex]::Replace($fact, "(dır|dir|dur|dür|tır|tir|tur|tür)$", "", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    } else {
        $fact = [Regex]::Replace($fact, "^(a|an|the)?\s*$term\s*,?\s*", "", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $fact = [Regex]::Replace($fact, "\b$term\b\s*,?\s*", "", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    $fact = [Regex]::Replace($fact, "\s+", " ").Trim().Trim(",").Trim()
    if ([string]::IsNullOrWhiteSpace($fact)) { $fact = $topic.answer }
    return Start-WithCapital $fact $lang
}

function Pick-TermWrongs($topics, $correctTerm, $offset, $lang) {
    $picked = @()
    $i = $offset
    while ($picked.Count -lt 3) {
        $candidate = Start-WithCapital $topics[$i % $topics.Count].term $lang
        if ($candidate -ne $correctTerm -and ($picked -notcontains $candidate)) {
            $picked += $candidate
        }
        $i++
        if ($i -gt ($offset + $topics.Count + 8)) {
            throw "Yeterli yanlış seçenek bulunamadı: $correctTerm"
        }
    }
    return $picked
}

function Get-InverseQuestionTemplates($lang, $categoryKey) {
    if ($lang -eq "tr") {
        if ($categoryKey -eq "spor") {
            return @(
                "{clue} hangi spor terimidir?",
                "{clue} hangi kavramla adlandırılır?",
                "{clue} denince hangi terim akla gelir?",
                "{clue} hangi spor kavramını anlatır?",
                "{clue} hangi terimle açıklanır?",
                "{clue} aşağıdakilerden hangisidir?",
                "{clue} hangi başlıkla doğru eşleşir?",
                "{clue} sporda hangi kavramdır?",
                "{clue} hangi adla bilinir?",
                "{clue} hangi spor başlığına karşılık gelir?",
                "{clue} hangi spor terimiyle ifade edilir?",
                "{clue} hangi terimin açıklamasıdır?",
                "{clue} hangi kavramın açıklamasıdır?",
                "{clue} sporda hangi ifadeyle bilinir?",
                "{clue} hangi spor ifadesine karşılık gelir?",
                "{clue} hangi kavramın tanımıdır?",
                "{clue} hangi terimin tanımıdır?"
            )
        }
        return @(
            "{clue} hangi kavramdır?",
            "{clue} hangi terimle adlandırılır?",
            "{clue} denince hangi kavram akla gelir?",
            "{clue} hangi kavramı anlatır?",
            "{clue} hangi terimle açıklanır?",
            "{clue} aşağıdakilerden hangisidir?",
            "{clue} hangi başlıkla doğru eşleşir?",
            "{clue} hangi adla bilinir?",
            "{clue} hangi kavramın açıklamasıdır?",
            "{clue} hangi terimin açıklamasıdır?",
            "{clue} hangi ifadeye karşılık gelir?",
            "{clue} hangi kavramın tanımıdır?",
            "{clue} hangi terimin tanımıdır?"
        )
    }
    return @(
        "Which term matches this explanation: {clue}?",
        "Which concept is described by {clue}?",
        "What is the name for {clue}?",
        "Which option best matches {clue}?"
    )
}

function Get-DirectQuestionTemplates($lang, $placeholder) {
    if ($lang -eq "tr") {
        return @(
            "$placeholder nedir?",
            "$placeholder ne demektir?",
            "$placeholder ne anlama gelir?",
            "$placeholder nasıl tanımlanır?",
            "$placeholder nasıl açıklanır?",
            "$placeholder neye denir?",
            "$placeholder hangi anlama gelir?",
            "$placeholder ne olarak bilinir?",
            "$placeholder terim olarak ne demektir?",
            "$placeholder kavramı ne anlama gelir?",
            "$placeholder ifadesi ne anlama gelir?",
            "$placeholder denince ne anlaşılır?",
            "$placeholder denildiğinde ne anlaşılır?",
            "$placeholder neyin adıdır?",
            "$placeholder ne olarak adlandırılır?",
            "$placeholder hangi anlamıyla bilinir?",
            "$placeholder hangi tanımla bilinir?",
            "$placeholder sözcüğü ne anlama gelir?",
            "$placeholder terimi hangi anlama gelir?",
            "$placeholder ifadesi hangi anlama gelir?",
            "$placeholder hangi kavrama verilen addır?",
            "$placeholder hangi tanımla açıklanır?",
            "$placeholder hangi açıklamayla tanımlanır?",
            "$placeholder için doğru tanım hangisidir?",
            "$placeholder hangi anlamda kullanılır?",
            "$placeholder genel anlamda nedir?",
            "$placeholder temel olarak nedir?",
            "$placeholder sözlükte ne anlama gelir?",
            "$placeholder hangi temel anlama gelir?",
            "$placeholder hangi açıklamaya karşılık gelir?",
            "$placeholder hangi tanıma karşılık gelir?",
            "$placeholder aşağıdakilerden hangisidir?",
            "$placeholder için doğru açıklama hangisidir?",
            "$placeholder ile ilgili doğru bilgi hangisidir?",
            "$placeholder kavramı aşağıdakilerden hangisidir?",
            "$placeholder terimi aşağıdakilerden hangisidir?",
            "$placeholder hangi açıklamayla eşleşir?",
            "$placeholder aşağıdakilerden hangisini anlatır?",
            "$placeholder kavramı aşağıdakilerden hangisini anlatır?",
            "$placeholder terimi aşağıdakilerden hangisini anlatır?"
        )
    }
    if ($lang -eq "tr") {
        $tails = @(
            "nedir?",
            "ne demektir?",
            "ne anlama gelir?",
            "neye denir?",
            "hangi anlama gelir?",
            "teriminin anlamı nedir?",
            "kavramının anlamı nedir?",
            "nasıl tanımlanır?",
            "nasıl açıklanır?",
            "kavramı nasıl açıklanır?",
            "kavramı nasıl tanımlanır?",
            "terimi nasıl açıklanır?",
            "terimi nasıl tanımlanır?",
            "için kısa tanım nedir?",
            "için kısa açıklama nedir?",
            "temel anlamı nedir?",
            "temel tanımı nedir?",
            "kısa tanımı nedir?",
            "sözlük anlamı nedir?",
            "yalın tanımı nedir?",
            "basitçe nedir?",
            "temelde ne demektir?",
            "ne olarak tanımlanır?",
            "ne olarak açıklanır?",
            "ne olarak bilinir?",
            "hangi anlamı taşır?",
            "hangi anlamda kullanılır?",
            "hangi anlamla kullanılır?",
            "hangi kavramı karşılar?",
            "hangi tanımla anlatılır?",
            "hangi açıklamayla anlatılır?",
            "hangi kullanımı anlatır?",
            "hangi görevi açıklar?",
            "hangi işlevi anlatır?",
            "hangi örneği anlatır?",
            "hangi durumu açıklar?",
            "hangi yapıyı açıklar?",
            "hangi ilişkiyi açıklar?",
            "hangi farkı anlatır?",
            "hangi sistemi açıklar?",
            "hangi başlığı anlatır?",
            "hangi bilgiyi açıklar?",
            "hangi alanda kullanılır?",
            "ne amaçla kullanılır?",
            "ne için kullanılır?",
            "nerede kullanılır?",
            "neden önemlidir?",
            "neye yarar?",
            "ne işe yarar?",
            "hangi işleve sahiptir?",
            "hangi kullanım için bilinir?",
            "nasıl anlaşılır?",
            "nasıl yorumlanır?",
            "terim olarak nedir?",
            "terim olarak ne demektir?",
            "terim olarak ne anlama gelir?",
            "terim olarak nasıl açıklanır?",
            "terim olarak nasıl tanımlanır?",
            "kavram olarak nedir?",
            "kavram olarak ne demektir?",
            "kavram olarak ne anlama gelir?",
            "kavram olarak nasıl açıklanır?",
            "kavram olarak nasıl tanımlanır?",
            "anlam olarak nedir?",
            "anlam olarak ne demektir?",
            "tanım olarak nedir?",
            "tanım olarak ne demektir?",
            "açıklama olarak nedir?",
            "açıklama olarak ne demektir?",
            "sade tanımı nedir?",
            "basit tanımı nedir?",
            "kolay tanımı nedir?",
            "net tanımı nedir?",
            "açık tanımı nedir?",
            "ana anlamı nedir?",
            "başlıca anlamı nedir?",
            "kullanım anlamı nedir?",
            "temel kullanımı nedir?",
            "başlıca kullanımı nedir?",
            "ana işlevi nedir?",
            "başlıca işlevi nedir?",
            "temel işlevi nedir?",
            "en kısa tanımı nedir?",
            "en yalın tanımı nedir?",
            "en net tanımı nedir?",
            "en açık tanımı nedir?",
            "hangi ana anlamı taşır?",
            "hangi başlıca anlamı taşır?",
            "hangi işlevle bilinir?",
            "hangi görevle bilinir?",
            "hangi kullanımla bilinir?",
            "hangi tanımla bilinir?",
            "hangi açıklamayla bilinir?",
            "hangi konu başlığını anlatır?",
            "hangi konu başlığını açıklar?",
            "hangi kullanım alanını anlatır?",
            "hangi kullanım alanını açıklar?",
            "hangi işlev alanını anlatır?",
            "hangi işlev alanını açıklar?",
            "hangi örnek alanını anlatır?",
            "hangi örnek alanını açıklar?",
            "hangi anlam alanını anlatır?",
            "hangi anlam alanını açıklar?",
            "hangi tanım alanına girer?",
            "hangi açıklama alanına girer?",
            "hangi görev alanına girer?",
            "hangi kullanım alanına girer?",
            "hangi konu alanına girer?",
            "hangi kavram alanına girer?",
            "hangi terim alanına girer?",
            "hangi anlam alanına girer?",
            "hangi yalın anlama gelir?",
            "hangi net anlama gelir?",
            "hangi açık anlama gelir?",
            "hangi kısa anlama gelir?",
            "hangi sade anlama gelir?"
        )
    } else {
        $tails = @(
            "means what?",
            "is used for what?",
            "is known as what?",
            "refers to what?",
            "is mainly about what?",
            "serves which purpose?",
            "gives which information?",
            "has which function?",
            "is used in which sense?",
            "is known for which feature?",
            "describes which task?",
            "is recognized by which fact?",
            "points to which meaning?",
            "is best defined as what?",
            "shows which basic use?",
            "relates to which result?",
            "is explained by which example?",
            "has which practical meaning?",
            "is linked to which idea?",
            "belongs to which area?",
            "explains which situation?",
            "shows which relation?",
            "supports which use?",
            "has which role?",
            "answers which need?",
            "is useful for what?",
            "describes which result?",
            "shows which difference?",
            "has which meaning?",
            "is part of which topic?",
            "is seen in which case?",
            "serves which function?",
            "is connected with what?",
            "helps explain what?",
            "is used in which field?",
            "shows which signal?",
            "is linked with which process?",
            "is related to which topic?",
            "is known in which way?",
            "helps with which task?",
            "is used for which purpose?",
            "explains which point?",
            "describes which structure?",
            "is tied to which need?",
            "is useful in which situation?",
            "shows which kind of information?",
            "is learned for which reason?",
            "answers which question?",
            "is associated with which result?",
            "is connected to which area?",
            "has which practical use?",
            "is understood as what?",
            "is remembered for what?",
            "is used to explain what?",
            "is linked with which meaning?",
            "is part of which system?",
            "is important in which way?",
            "is used around which subject?",
            "is known by which use?",
            "points to which answer?",
            "describes which concept?",
            "explains which idea?",
            "shows which purpose?",
            "is about which matter?",
            "is useful in which field?",
            "connects to which meaning?",
            "is defined by what?",
            "is used to show what?",
            "is related to what?",
            "is important for what?",
            "serves what kind of role?",
            "shows what kind of result?",
            "has which clear meaning?",
            "has which short meaning?",
            "has which direct meaning?",
            "has which main meaning?",
            "has which clean meaning?",
            "has which basic meaning?",
            "has which clear definition?",
            "has which short definition?",
            "has which direct definition?",
            "has which main definition?",
            "has which clean definition?",
            "has which basic definition?",
            "is explained by which clear answer?",
            "is explained by which short answer?",
            "is explained by which direct answer?",
            "is explained by which main answer?",
            "is explained by which clean answer?",
            "is explained by which basic answer?",
            "is best described by what?",
            "is most clearly described as what?",
            "is most directly described as what?",
            "is most simply described as what?",
            "is mainly described as what?",
            "is correctly described as what?",
            "is best explained by what?",
            "is most clearly explained by what?",
            "is most directly explained by what?",
            "is most simply explained by what?",
            "is mainly explained by what?",
            "is correctly explained by what?",
            "is best understood as what?",
            "is most clearly understood as what?",
            "is most directly understood as what?",
            "is most simply understood as what?",
            "is mainly understood as what?",
            "is correctly understood as what?",
            "covers which clear idea?",
            "covers which short idea?",
            "covers which direct idea?",
            "covers which main idea?",
            "covers which basic idea?",
            "matches which clear idea?",
            "matches which short idea?",
            "matches which direct idea?",
            "matches which main idea?",
            "matches which basic idea?",
            "points to which clear answer?",
            "points to which short answer?",
            "points to which direct answer?",
            "points to which main answer?",
            "points to which basic answer?"
        )
    }
    $out = @()
    foreach ($tail in $tails) {
        $out += "$placeholder $tail"
    }
    return @($out | Select-Object -Unique)
}

function Get-SportQuestionTemplates($placeholder) {
    $tails = @(
        "nedir?",
        "ne demektir?",
        "ne anlama gelir?",
        "neye denir?",
        "nasıl tanımlanır?",
        "nasıl açıklanır?",
        "sporda ne demektir?",
        "sporda ne anlama gelir?",
        "sporda nasıl tanımlanır?",
        "sporda nasıl açıklanır?"
    )
    $out = @()
    foreach ($tail in $tails) {
        $out += "$placeholder $tail"
    }
    return @($out | Select-Object -Unique)
}

function Test-HistoryPersonTerm($lang, $categoryKey, $term) {
    if ($categoryKey -ne "tarih") { return $false }
    if ($lang -eq "tr") {
        return $term -match "Atatürk|Fatih|Sultan|Osman Bey|Selim|Kanuni|Mimar Sinan|Bey"
    }
    return $term -match "Atatürk|Mehmed|Conqueror|Selim|Suleiman|Osman|Sinan"
}

function Get-HistoryPersonTemplates($lang, $placeholder) {
    if ($lang -eq "tr") {
        $subjects = @(
            $placeholder,
            "$placeholder tarihte",
            "$placeholder tarih dersinde"
        )
        $tails = @(
            "hangi olayla bilinir?",
            "hangi başarıyla bilinir?",
            "hangi olayla anılır?",
            "hangi başarıyla anılır?",
            "neyle bilinir?",
            "neyi başarmıştır?",
            "hangi tarihsel olayla ilişkilidir?",
            "hangi dönemle ilişkilidir?"
        )
    } else {
        $subjects = @(
            $placeholder,
            "$placeholder in history",
            "a history lesson on $placeholder",
            "the figure $placeholder",
            "the historical name $placeholder"
        )
        $tails = @(
            "is known for which event or role?",
            "is known for which achievement?",
            "is linked with which historical fact?",
            "is associated with which event?",
            "stands out for which role?",
            "belongs to which historical heading?",
            "connects to which historical result?",
            "matches which history answer?",
            "is remembered for which event?",
            "is tied to which achievement?"
        )
    }
    $out = @()
    foreach ($subject in $subjects) {
        foreach ($tail in $tails) {
            $out += "$subject $tail"
        }
    }
    return @($out | Select-Object -Unique)
}

function Get-EasyTemplates($lang, $categoryKey = "") {
    if ($lang -eq "tr" -and $categoryKey -eq "spor") {
        return Get-SportQuestionTemplates "{term}"
    }
    if ($lang -eq "tr") {
        return Get-DirectQuestionTemplates $lang "{term}"
    }
    return Get-DirectQuestionTemplates $lang "{term}"
}

function Pick-EasyWrongs($lang, $categoryKey, $correctAnswer, $offset) {
    $source = if ($lang -eq "tr") { $wrongTrByCategory } else { $wrongEnByCategory }
    $pool = @($source[$categoryKey])
    return Pick-Wrongs $pool $correctAnswer $offset
}

function New-SimpleFact($stem, $answer, [string[]]$wrongs, $fact) {
    [PSCustomObject]@{
        stem   = $stem
        answer = $answer
        wrongs = $wrongs
        fact   = $fact
    }
}

function Parse-SimpleFacts([string[]]$rows) {
    $facts = @()
    foreach ($row in $rows) {
        $parts = $row -split "\|", 4
        if ($parts.Count -ne 4) {
            throw "Kolay soru satırı hatalı: $row"
        }
        $wrongs = $parts[2] -split ","
        if ($wrongs.Count -ne 3) {
            throw "Kolay soru yanlışları 3 adet olmalı: $row"
        }
        $facts += New-SimpleFact $parts[0] $parts[1] $wrongs $parts[3]
    }
    return $facts
}

function Get-SimpleQuestionTemplates($lang) {
    if ($lang -eq "tr") {
        return @("{stem}?")
    } else {
        return @("{stem}?")
    }
}

function New-YearFact($subject, $answer, [string[]]$wrongs, $fact) {
    [PSCustomObject]@{
        subject = $subject
        answer  = $answer
        wrongs  = $wrongs
        fact    = $fact
    }
}

function Get-YearTemplatesTr($subject) {
    if ($subject -eq "Atatürk'ün doğumu") {
        return @(
            "Atatürk hangi yıl doğmuştur?",
            "Atatürk kaç yılında doğmuştur?",
            "Mustafa Kemal Atatürk hangi yıl doğmuştur?",
            "Mustafa Kemal Atatürk kaç yılında doğmuştur?"
        )
    }
    if ($subject -match "Antlaşması|Sözleşmesi|Sened-i") {
        return @(
            "{subject} hangi yılda imzalanmıştır?",
            "{subject} hangi tarihte imzalanmıştır?",
            "{subject} kaç yılında imzalanmıştır?",
            "{subject} hangi yıl imzalanmıştır?",
            "{subject} ne zaman imzalanmıştır?",
            "{subject} hangi yılda kabul edilmiştir?"
        )
    }
    if ($subject -match "Fermanı|Meşrutiyet|Kanunu|Magna Carta|anayasa") {
        return @(
            "{subject} hangi yılda kabul edilmiştir?",
            "{subject} hangi tarihte kabul edilmiştir?",
            "{subject} kaç yılında kabul edilmiştir?",
            "{subject} hangi yıl kabul edilmiştir?",
            "{subject} ne zaman kabul edilmiştir?"
        )
    }
    if ($subject -eq "Türkiye Cumhuriyeti'nin ilanı") {
        return @(
            "Türkiye Cumhuriyeti hangi yılda ilan edilmiştir?",
            "Türkiye Cumhuriyeti kaç yılında ilan edilmiştir?",
            "Cumhuriyet hangi yıl ilan edilmiştir?",
            "Türkiye Cumhuriyeti hangi yıl ilan edilmiştir?"
        )
    }
    if ($subject -eq "KKTC'nin ilanı") {
        return @(
            "KKTC hangi yılda ilan edilmiştir?",
            "KKTC kaç yılında ilan edilmiştir?",
            "Kuzey Kıbrıs Türk Cumhuriyeti hangi yıl ilan edilmiştir?",
            "Kuzey Kıbrıs Türk Cumhuriyeti ne zaman ilan edilmiştir?"
        )
    }
    if ($subject -eq "Ankara'nın başkent oluşu") {
        return @(
            "Ankara hangi yılda başkent olmuştur?",
            "Ankara kaç yılında başkent olmuştur?",
            "Ankara hangi yıl başkent olmuştur?",
            "Ankara ne zaman başkent olmuştur?"
        )
    }
    if ($subject -match "ilanı|başkent oluşu") {
        return @(
            "{subject} hangi yılda ilan edilmiştir?",
            "{subject} hangi tarihte ilan edilmiştir?",
            "{subject} kaç yılında ilan edilmiştir?",
            "{subject} hangi yıl ilan edilmiştir?",
            "{subject} ne zaman ilan edilmiştir?"
        )
    }
    if ($subject -match "kuruluşu") {
        return @(
            "{subject} hangi yıldadır?",
            "{subject} kaç yılında gerçekleşmiştir?",
            "{subject} hangi yıl kabul edilir?",
            "{subject} hangi yılla bilinir?"
        )
    }
    if ($subject -match "bitişi|sona ermesi|yıkılışı|kaldırılması") {
        return @(
            "{subject} hangi yılda gerçekleşmiştir?",
            "{subject} kaç yılında olmuştur?",
            "{subject} hangi yıl olmuştur?",
            "{subject} ne zaman gerçekleşmiştir?"
        )
    }
    if ($subject -match "Savaşı|Muharebesi|Zaferi|Taarruz|İhtilali|Devrimi|Göçü|fethi|çıkışı|Kongresi|Genelgesi") {
        return @(
            "{subject} hangi yılda gerçekleşmiştir?",
            "{subject} hangi tarihte gerçekleşmiştir?",
            "{subject} kaç yılında gerçekleşmiştir?",
            "{subject} hangi yıl gerçekleşti?",
            "{subject} ne zaman gerçekleşmiştir?",
            "{subject} hangi yılda yapılmıştır?"
        )
    }
    return @(
        "{subject} hangi yılda gerçekleşmiştir?",
        "{subject} kaç yılında olmuştur?",
        "{subject} hangi yıl olmuştur?",
        "{subject} ne zaman gerçekleşmiştir?"
    )
}

function New-YearFactBank($lang, $categoryKey, $categoryName, $facts, $maxCount) {
    if ($facts.Count -eq 0 -or $maxCount -le 0) { return @() }
    $templates = if ($lang -eq "tr") { @() } else {
        @(
            "In which year did {subject} happen?",
            "Which year is correct for {subject}?",
            "{subject} is associated with which year?",
            "Which year matches {subject}?",
            "In which year did {subject} take place?",
            "What year is linked to {subject}?",
            "Which year should be selected for {subject}?",
            "Which year is recorded for {subject}?",
            "{subject} took place in which year?",
            "Which answer gives the year of {subject}?",
            "Which year is remembered for {subject}?",
            "Which year best matches {subject}?",
            "What is the correct year for {subject}?",
            "Which year did {subject} occur?",
            "Which year identifies {subject}?",
            "Which date year fits {subject}?",
            "Which historical year belongs to {subject}?",
            "Which year is known for {subject}?",
            "Which option gives the right year for {subject}?",
            "Which year should be linked with {subject}?"
        )
    }
    $items = @()
    $maxTemplateCount = if ($lang -eq "tr") {
        ($facts | ForEach-Object { (Get-YearTemplatesTr $_.subject).Count } | Measure-Object -Maximum).Maximum
    } else { $templates.Count }
    for ($round = 0; $round -lt $maxTemplateCount -and $items.Count -lt $maxCount; $round++) {
        for ($f = 0; $f -lt $facts.Count -and $items.Count -lt $maxCount; $f++) {
        $fact = $facts[$f]
        $templateBank = if ($lang -eq "tr") { Get-YearTemplatesTr $fact.subject } else { $templates }
        if ($round -ge $templateBank.Count) { continue }
        $template = $templateBank[$round]
        $i = $items.Count
        $question = $template.Replace("{subject}", $fact.subject)
        $answers = @($null, $null, $null, $null)
        $correctIndex = ($i + $categoryKey.Length + 1) % 4
        $answers[$correctIndex] = $fact.answer
        $w = 0
        for ($a = 0; $a -lt 4; $a++) {
            if ($a -ne $correctIndex) {
                $answers[$a] = Start-WithCapital $fact.wrongs[$w] $lang
                $w++
            }
        }
        Assert-QuestionAnswerTypes $question $answers "$lang/$categoryKey/fact"
        $items += [PSCustomObject]@{
            id         = "{0}-{1}-fact-{2:d5}" -f $lang, $categoryKey, ($i + 1)
            category   = $categoryName
            difficulty = switch ($i % 3) {
                0 { if ($lang -eq "tr") { "kolay" } else { "easy" } }
                1 { if ($lang -eq "tr") { "orta" } else { "medium" } }
                default { if ($lang -eq "tr") { "zor" } else { "hard" } }
            }
            question   = $question
            answers    = $answers
            correct    = $correctIndex
            fact       = $fact.fact
        }
        }
    }
    return $items
}

function New-QuestionBank($lang, $categoryKey, $categoryName, $topics, $templates, $factOpeners, $wrongBank, $perCategory, $simpleFacts) {
    $items = @()
    $usedQuestions = @{}
    $questionTemplates = @($templates)
    $simpleQuestionTemplates = @(Get-SimpleQuestionTemplates $lang)
    $easyTemplates = @(Get-EasyTemplates $lang $categoryKey)
    $inverseTemplates = @(Get-InverseQuestionTemplates $lang $categoryKey)
    $historyPersonTemplates = @(Get-HistoryPersonTemplates $lang "{term}")
    $historyDefinitionTemplates = @(Get-HistoryPersonTemplates $lang "{definition}")
    $focusTemplateBank = @()
    if ($lang -eq "tr" -and $script:genericFocusTemplatesTr) {
        $focusTemplateBank = @($script:genericFocusTemplatesTr)
    } elseif ($lang -eq "en" -and $script:focusTemplatesEn -and $script:focusTemplatesEn.ContainsKey($categoryKey)) {
        $focusTemplateBank = @($script:focusTemplatesEn[$categoryKey])
    } elseif ($lang -eq "en" -and $script:genericFocusTemplatesEn) {
        $focusTemplateBank = @($script:genericFocusTemplatesEn)
    }
    $estimatedTemplateCapacity = @($questionTemplates + $easyTemplates + $inverseTemplates + $historyPersonTemplates + $historyDefinitionTemplates + $focusTemplateBank | Select-Object -Unique).Count
    $baseCapacity = $topics.Count * $estimatedTemplateCapacity
    if ($baseCapacity -lt $perCategory) {
        throw "$lang/$categoryKey için üretim kapasitesi yetersiz. Kapasite: $baseCapacity, istenen: $perCategory"
    }
    $easyCounter = 0
    for ($i = 0; $items.Count -lt $perCategory -and $i -lt ($perCategory * 10); $i++) {
        $topic = $topics[$i % $topics.Count]
        $difficulty = switch ($i % 3) {
            0 { if ($lang -eq "tr") { "kolay" } else { "easy" } }
            1 { if ($lang -eq "tr") { "orta" } else { "medium" } }
            default { if ($lang -eq "tr") { "zor" } else { "hard" } }
        }

        $isEasyDifficulty = ($difficulty -eq "kolay" -or $difficulty -eq "easy")
        $isHardDifficulty = ($difficulty -eq "zor" -or $difficulty -eq "hard")
        if ($isEasyDifficulty -and $simpleFacts -and $simpleFacts.Count -gt 0 -and $easyCounter -lt $simpleFacts.Count) {
            $simple = $simpleFacts[$easyCounter % $simpleFacts.Count]
            $template = $simpleQuestionTemplates[[int][Math]::Floor($easyCounter / $simpleFacts.Count) % $simpleQuestionTemplates.Count]
            $question = New-QuestionText ($template.Replace("{stem}", $simple.stem)) $lang 0
            $correctAnswer = $simple.answer
            $wrongs = $simple.wrongs
            $factText = $simple.fact
            $easyCounter++
        } elseif (-not $isEasyDifficulty -and $lang -eq "tr" -and $inverseTemplates.Count -gt 0 -and (($i % 4) -eq 1 -or ($i % 7) -eq 3)) {
            $template = $inverseTemplates[[int][Math]::Floor($i / $topics.Count) % $inverseTemplates.Count]
            $term = Start-WithCapital $topic.term $lang
            $clue = New-DefinitionClue $topic $lang
            $question = New-QuestionText ($template.Replace("{clue}", $clue).Replace("{term}", $term)) $lang 0
            $correctAnswer = $term
            $wrongs = Pick-TermWrongs $topics $correctAnswer ($i + ($categoryKey.Length * 13)) $lang
            $factText = $topic.fact
        } elseif ($difficulty -eq "kolay" -or $difficulty -eq "easy") {
            $templateBank = if (Test-HistoryPersonTerm $lang $categoryKey $topic.term) { $historyPersonTemplates } else { @($easyTemplates + $questionTemplates) }
            $template = $templateBank[[int][Math]::Floor($i / $topics.Count) % $templateBank.Count]
            $term = Start-WithCapital $topic.term $lang
            $question = New-QuestionText (($template.Replace("{term}", $term)).Replace("{definition}", $term)) $lang 0
            $correctAnswer = Start-WithCapital $topic.answer $lang
            $wrongs = Pick-EasyWrongs $lang $categoryKey $correctAnswer ($i + ($categoryKey.Length * 11))
            $factText = $topic.fact
        } else {
            $templateBank = if (Test-HistoryPersonTerm $lang $categoryKey $topic.term) {
                $historyDefinitionTemplates
            } elseif ($isHardDifficulty -and $focusTemplateBank.Count -gt 0) {
                $focusTemplateBank
            } else {
                $questionTemplates
            }
            $template = $templateBank[[int][Math]::Floor($i / $topics.Count) % $templateBank.Count]
            $term = Start-WithCapital $topic.term $lang
            $baseQuestion = ($template.Replace("{definition}", $term)).Replace("{term}", $term)
            $question = New-QuestionText $baseQuestion $lang 0
            $correctAnswer = Start-WithCapital $topic.answer $lang
            $wrongs = Pick-Wrongs $wrongBank $correctAnswer ($i + ($categoryKey.Length * 7))
            $factText = $topic.fact
        }
        if (Use-NominativeAnswer $question $lang) {
            $correctAnswer = Start-WithCapital (Convert-ToNominativeTr $correctAnswer) $lang
            $convertedWrongs = @()
            foreach ($wrong in $wrongs) {
                $convertedWrongs += Start-WithCapital (Convert-ToNominativeTr $wrong) $lang
            }
            $wrongs = $convertedWrongs
        }
        $answers = @($null, $null, $null, $null)
        $correctIndex = ($i + $categoryKey.Length) % 4
        $answers[$correctIndex] = $correctAnswer
        $w = 0
        for ($a = 0; $a -lt 4; $a++) {
            if ($a -ne $correctIndex) {
                $answers[$a] = Start-WithCapital $wrongs[$w] $lang
                $w++
            }
        }
        if (Test-QuestionAnswerMismatch $question $correctAnswer $answers $lang) { continue }
        Assert-QuestionAnswerTypes $question $answers "$lang/$categoryKey"
        if ($factText.Length -lt 20) {
            if ($lang -eq "tr") { $factText = "$factText Bu kolay genel kültür bilgisidir." }
            else { $factText = "$factText This is a basic general knowledge fact." }
        }

        if ($usedQuestions.ContainsKey($question)) { continue }
        $usedQuestions[$question] = $true

        $items += [PSCustomObject]@{
            id         = "{0}-{1}-{2:d5}" -f $lang, $categoryKey, ($items.Count + 1)
            category   = $categoryName
            difficulty = $difficulty
            question   = $question
            answers    = $answers
            correct    = $correctIndex
            fact       = $factText
        }
    }
    if ($items.Count -lt $perCategory) {
        for ($round = 0; $items.Count -lt $perCategory -and $round -lt ($questionTemplates.Count * 3); $round++) {
            for ($topicIndex = 0; $topicIndex -lt $topics.Count -and $items.Count -lt $perCategory; $topicIndex++) {
                $topic = $topics[($topicIndex + $round) % $topics.Count]
                $difficulty = switch ($items.Count % 3) {
                    0 { if ($lang -eq "tr") { "kolay" } else { "easy" } }
                    1 { if ($lang -eq "tr") { "orta" } else { "medium" } }
                    default { if ($lang -eq "tr") { "zor" } else { "hard" } }
                }
                $isFillEasy = ($difficulty -eq "kolay" -or $difficulty -eq "easy")
                $useInverseFill = (-not $isFillEasy -and $lang -eq "tr" -and $inverseTemplates.Count -gt 0 -and (($round + $topicIndex) % 2 -eq 0))
                $template = if ($useInverseFill) { $inverseTemplates[$round % $inverseTemplates.Count] } else { $questionTemplates[$round % $questionTemplates.Count] }
                $term = Start-WithCapital $topic.term $lang
                if ($useInverseFill) {
                    $clue = New-DefinitionClue $topic $lang
                    $question = New-QuestionText ($template.Replace("{clue}", $clue).Replace("{term}", $term)) $lang 0
                } else {
                    $question = New-QuestionText ($template.Replace("{definition}", $term)) $lang 0
                }
                if ($usedQuestions.ContainsKey($question)) { continue }
                if ($useInverseFill) {
                    $correctAnswer = $term
                    $wrongs = Pick-TermWrongs $topics $correctAnswer ($round + $topicIndex + ($categoryKey.Length * 17)) $lang
                } else {
                    $correctAnswer = Start-WithCapital $topic.answer $lang
                    $wrongs = Pick-Wrongs $wrongBank $correctAnswer ($round + $topicIndex + ($categoryKey.Length * 17))
                }
                $factText = $topic.fact
                if (Use-NominativeAnswer $question $lang) {
                    $correctAnswer = Start-WithCapital (Convert-ToNominativeTr $correctAnswer) $lang
                    $convertedWrongs = @()
                    foreach ($wrong in $wrongs) {
                        $convertedWrongs += Start-WithCapital (Convert-ToNominativeTr $wrong) $lang
                    }
                    $wrongs = $convertedWrongs
                }
                $answers = @($null, $null, $null, $null)
                $correctIndex = ($items.Count + $categoryKey.Length) % 4
                $answers[$correctIndex] = $correctAnswer
                $w = 0
                for ($a = 0; $a -lt 4; $a++) {
                    if ($a -ne $correctIndex) {
                        $answers[$a] = Start-WithCapital $wrongs[$w] $lang
                        $w++
                    }
                }
                if (Test-QuestionAnswerMismatch $question $correctAnswer $answers $lang) { continue }
                Assert-QuestionAnswerTypes $question $answers "$lang/$categoryKey/fill"
                if ($factText.Length -lt 20) {
                    if ($lang -eq "tr") { $factText = "$factText Bu kolay genel kültür bilgisidir." }
                    else { $factText = "$factText This is a basic general knowledge fact." }
                }
                $usedQuestions[$question] = $true
                $items += [PSCustomObject]@{
                    id         = "{0}-{1}-{2:d5}" -f $lang, $categoryKey, ($items.Count + 1)
                    category   = $categoryName
                    difficulty = $difficulty
                    question   = $question
                    answers    = $answers
                    correct    = $correctIndex
                    fact       = $factText
                }
            }
        }
    }
    if ($items.Count -lt $perCategory) {
        throw "$lang/$categoryKey için benzersiz soru üretilemedi. Üretilen: $($items.Count), istenen: $perCategory"
    }
    return $items
}

$templatesTr = @(
    "{term} nedir?",
    "{term} ne demektir?",
    "{term} ne anlama gelir?",
    "{term} neyi ifade eder?",
    "{term} neyi anlatır?",
    "{term} neyi açıklar?",
    "{term} ne işe yarar?",
    "{term} hangi amaçla kullanılır?",
    "{term} hangi özellikle bilinir?",
    "{term} hangi işlevi görür?",
    "{term} hangi alanda kullanılır?",
    "{term} hangi konuyu anlatır?",
    "{term} hangi durumu gösterir?",
    "{term} hangi yapıyı anlatır?",
    "{term} hangi sonucu anlatır?",
    "{term} hangi ihtiyacı karşılar?",
    "{term} hangi görevi görür?",
    "{term} hangi kullanımla bilinir?",
    "{term} hangi anlama gelir?",
    "{term} hangi kavramı anlatır?",
    "{term} hangi başlıkla açıklanır?",
    "{term} hangi örnekle tanınır?",
    "{term} hangi düzeni gösterir?",
    "{term} hangi ilişkiyi anlatır?",
    "{term} hangi farkı açıklar?",
    "{term} hangi noktayı açıklar?",
    "{term} hangi sistemi anlatır?",
    "{term} hangi amaç için vardır?",
    "{term} hangi durumda kullanılır?",
    "{term} hangi alanda önemlidir?",
    "{term} hangi özelliği taşır?",
    "{term} hangi kullanımı gösterir?",
    "{term} hangi konuya bağlıdır?",
    "{term} hangi soruna çözüm olur?",
    "{term} hangi ihtiyaca yanıt verir?",
    "{term} hangi sonucu doğurur?",
    "{term} hangi anlamı taşır?",
    "{term} hangi işleve karşılık gelir?",
    "{term} hangi örnekte kullanılır?",
    "{term} hangi durumlarda gerekir?"
)

$templatesEn = @(
    "What is the best short meaning of {term}?",
    "Which statement fits {term} best?",
    "In simple terms, what does {term} point to?",
    "Which option is correct about {term}?",
    "What is the core idea behind {term}?",
    "In daily life, what does {term} usually mean?",
    "Which safe interpretation fits {term}?",
    "What does {term} mainly highlight?",
    "Which answer matches the topic {term}?",
    "Which reading of {term} avoids a mistake?",
    "What explains {term} most clearly?",
    "When you hear {term}, what idea matters?",
    "Why is {term} an important concept?",
    "What is {term} trying to describe?",
    "What is the quick answer for {term}?",
    "Which option gives the right idea for {term}?",
    "Which choice is most logical for {term}?",
    "What basic relation does {term} show?",
    "What is the simple correct answer for {term}?",
    "What should you know to understand {term}?",
    "Which idea does {term} support?",
    "Which short summary fits {term}?",
    "What can {term} be a sign of?",
    "Which short note about {term} is right?",
    "Which choice should be picked for {term}?",
    "Which option gives the right answer for {term}?",
    "Which meaning matches the heading {term}?",
    "What is the cleanest explanation of {term}?",
    "What key point does {term} remind us of?",
    "What comes first when judging {term}?",
    "What is the core of the phrase {term}?",
    "Which option about {term} is not wrong?",
    "Which simple reading of {term} is correct?",
    "Which short definition fits {term}?",
    "What answer fits when learning {term}?",
    "Which phrase wraps up {term}?",
    "What is the practical meaning of {term}?",
    "What is the main message in {term}?",
    "Which true note explains {term}?",
    "In its plainest form, what is {term}?"
)

$focusTemplatesTr = @{
    ekonomi = @(
        "Bir market, banka ya da yatırım haberinde {term} geçerse ne anlamalıyız?",
        "{term} konuşulurken çoğu kişinin kaçırdığı ana nokta hangisidir?",
        "Ekonomi haberinde {term} denince hangi açıklama daha yerindedir?",
        "{term} günlük bütçeyi hangi fikir üzerinden etkiler?",
        "{term} için arkadaşına tek cümleyle ne dersin?",
        "{term} neden fiyat, gelir veya borç kararlarında önem kazanır?",
        "{term} yükseldi ya da düştü denince aslında ne değişmiş olur?",
        "{term} yorumlanmadan önce hangi anlam bilinmeli?",
        "{term} sade anlatımda hangi ekonomik ilişkiye oturur?",
        "{term} bir karar vericiye hangi sinyali verir?",
        "{term} için en doğru ekonomi okuması hangisidir?",
        "{term} tüketici ya da yatırımcı açısından hangi noktayı öne çıkarır?",
        "{term} neden tek başına değil bağlamıyla okunmalıdır?",
        "{term} haberini görünce hangi sonuç daha mantıklıdır?",
        "{term} aile bütçesine dolaylı olarak nasıl bağlanır?",
        "{term} piyasa dilinde hangi kısa anlama gelir?",
        "{term} için yanlış beklentiye düşmemek adına ne bilinmeli?",
        "{term} konusu genelde hangi dengeyi anlatır?",
        "{term} kararları hangi temel maliyetle ilişkilidir?",
        "{term} nedir?"
    )
    bilim = @(
        "Bir deneyde {term} inceleniyorsa temel amaç ne olabilir?",
        "{term} okul bilgisinden çıkıp günlük hayatta neyi açıklar?",
        "{term} için bilimsel olarak en güvenli ifade hangisidir?",
        "{term} neden gözlem ve kanıtla anlaşılır?",
        "{term} için çocuklara anlatılacak en net cevap hangisidir?",
        "{term} canlılar, madde veya evrenle ilgili neyi gösterir?",
        "{term} sorusunda hangi açıklama bilimle uyumludur?",
        "{term} ile ilgili yaygın yanılgıdan kaçınmak için ne bilinmeli?",
        "{term} bir olayın hangi tarafını açıklamaya yardım eder?",
        "{term} basit bir örnekle hangi fikre bağlanır?",
        "{term} için kesin konuşurken hangi temel bilgi gerekir?",
        "{term} bilimsel düşüncede neden önemlidir?",
        "{term} gözlenen bir durumu hangi nedenle açıklar?",
        "{term} için günlük hayatta hangi açıklama doğrudur?",
        "{term} hangi ölçüm, süreç ya da ilişkiyle ilgilidir?",
        "{term} sorusunda kulağa doğru gelen ama hatalı olmayan cevap hangisidir?",
        "{term} öğrenirken hangi ana fikir akılda kalmalı?",
        "{term} kavramı doğayı anlamada hangi görevi görür?",
        "{term} için sade bilim cevabı hangisidir?",
        "{term} neden ezber yerine mantıkla anlaşılır?"
    )
    guncel = @(
        "Bugün sosyal medyada {term} görürsen ilk neyi düşünmelisin?",
        "{term} günlük hayatta neden daha sık karşımıza çıkıyor?",
        "{term} nedir?",
        "{term} haberini değerlendirirken hangi seçenek daha sağlıklıdır?",
        "{term} insan davranışını veya toplumsal gündemi nasıl etkiler?",
        "{term} için hızlı karar vermeden önce hangi nokta önemlidir?",
        "{term} dijital dünyada hangi riski ya da fırsatı anlatır?",
        "{term} için en sade ve işe yarar açıklama hangisidir?",
        "{term} gündemdeyse hangi soru sorulmalıdır?",
        "{term} konusunda yanlış bilgiye düşmemek için ne yapılmalı?",
        "{term} modern yaşamda hangi alışkanlıkla ilişkilidir?",
        "{term} toplumda hangi algıyı veya sonucu doğurabilir?",
        "{term} ne anlama gelir?",
        "{term} karşısında kullanıcı ya da vatandaş neye dikkat etmeli?",
        "{term} neden yalnızca başlığa bakarak anlaşılmaz?",
        "{term} nasıl tanımlanır?",
        "{term} haberlerinde hangi kontrol noktası önemlidir?",
        "{term} hangi bilinçli davranışı öne çıkarır?",
        "{term} günlük kararlarımızı nasıl etkileyebilir?",
        "{term} konusu hangi temel kavramla açıklanır?"
    )
    muzik = @(
        "{term} müzikte hangi temel fikri anlatır?",
        "{term} müzikte neyi anlatır?",
        "{term} nedir?",
        "{term} dinlerken neyi fark ettirir?",
        "{term} müzik tarihinde neden önem kazanır?",
        "{term} ses, ritim ya da yorum açısından neyi açıklar?",
        "{term} sanatçı performansında hangi anlamı taşır?",
        "{term} konusunda yanlış bilgiye düşmemek için ne bilinmeli?",
        "{term} bir müzik olayını anlamada hangi ana fikri verir?",
        "{term} için kulakta kalacak kısa açıklama hangisidir?"
    )
    tarih = @(
        "{term} tarih bilgisinde hangi anlamla öne çıkar?",
        "{term} konuşulurken hangi bağlamı hatırlamak gerekir?",
        "{term} neden önemli tarihsel sonuçlara bağlanır?",
        "{term} tarih bilgisinde neyi anlatır?",
        "{term} hangi olay, kişi ya da dönemi anlamaya yardım eder?",
        "{term} tarih okurken hangi ana fikri verir?",
        "{term} için ezber yerine hangi ilişki önemlidir?",
        "{term} geçmiş ile bugün arasında hangi bağlantıyı kurar?",
        "{term} tarihsel olayları değerlendirirken hangi noktayı öne çıkarır?",
        "{term} için sade ve doğru açıklama hangisidir?"
    )
}

$focusTemplatesEn = @{
    ekonomi = @(
        "When {term} appears in money news, what should you understand first?",
        "What is the main point people often miss about {term}?",
        "Which explanation fits {term} in an economy headline?",
        "How does {term} connect to daily budgeting decisions?",
        "How would you explain {term} to a friend in one line?",
        "Why can {term} matter for prices, income or debt decisions?",
        "When {term} rises or falls, what is really changing?",
        "What should be known before making a quick call on {term}?",
        "In plain language, what economic relation does {term} describe?",
        "What signal can {term} give to decision makers?",
        "Which reading of {term} is the most useful?",
        "What does {term} remind consumers or investors to watch?",
        "Why should {term} be read with context?",
        "Which conclusion makes sense when you see {term} in the news?",
        "How can {term} connect indirectly to a household budget?",
        "What short meaning does {term} carry in market language?",
        "What avoids a wrong expectation about {term}?",
        "Which balance does {term} usually describe?",
        "Which core cost is {term} related to?",
        "What is a simple current reading of {term}?"
    )
    bilim = @(
        "If a study looks at {term}, what is the basic point?",
        "Beyond school facts, what can {term} explain in daily life?",
        "Which statement about {term} is scientifically safest?",
        "Why is {term} understood through evidence and observation?",
        "What is the clearest child-friendly answer for {term}?",
        "What does {term} show about life, matter or the universe?",
        "Which explanation of {term} fits science best?",
        "What helps avoid a common mistake about {term}?",
        "What side of an event can {term} help explain?",
        "Which idea does {term} connect to in a simple example?",
        "What basic fact is needed before speaking confidently about {term}?",
        "Why does {term} matter in scientific thinking?",
        "Which cause can {term} use to explain an observation?",
        "Which everyday explanation fits {term} best?",
        "Which measurement, process or relation is {term} about?",
        "Which answer about {term} is not misleading?",
        "What main idea should stay in mind when learning {term}?",
        "How does {term} help us understand nature?",
        "What is the simple science answer for {term}?",
        "Why is {term} better understood with logic than memorization?"
    )
    guncel = @(
        "If you see {term} on social media today, what should you think first?",
        "Why does {term} show up more often in daily life now?",
        "What should you know to react well to {term}?",
        "Which option is healthier when judging news about {term}?",
        "How can {term} affect behavior or public discussion?",
        "What matters before making a quick judgment about {term}?",
        "What risk or opportunity does {term} describe in digital life?",
        "What is the simplest useful explanation of {term}?",
        "When {term} is trending, which question should be asked?",
        "What helps avoid misinformation around {term}?",
        "Which modern habit is {term} related to?",
        "What perception or result can {term} create in society?",
        "Which comment on {term} is reliable?",
        "What should users or citizens watch with {term}?",
        "Why is {term} not understood from a headline alone?",
        "What is a short but correct reading of {term}?",
        "Which check matters in news about {term}?",
        "Which mindful behavior does {term} remind us of?",
        "How can {term} affect everyday decisions?",
        "Which core concept explains {term}?"
    )
    muzik = @(
        "What core music idea does {term} describe?",
        "When discussing a song, stage or artist, what does {term} point to?",
        "Which simple reading of {term} is correct?",
        "What detail does {term} help listeners notice?",
        "Why can {term} matter in music history?",
        "What does {term} explain about sound, rhythm or performance?",
        "What can {term} mean in an artist's performance?",
        "What avoids a common mistake about {term}?",
        "Which main idea helps explain {term} in a music event?",
        "What is the short memorable explanation of {term}?"
    )
    tarih = @(
        "What basic historical meaning does {term} carry?",
        "What context should be remembered when discussing {term}?",
        "Why can {term} connect to important historical outcomes?",
        "Which short comment about {term} is safest?",
        "Which event, person or period can {term} help explain?",
        "What main idea does {term} give when reading history?",
        "Which relation matters more than memorization for {term}?",
        "How can {term} connect past and present?",
        "What does {term} remind us when judging historical events?",
        "What is the simple correct explanation of {term}?"
    )
}

$genericFocusTemplatesTr = @(
    "{term} nedir?",
    "{term} ne demektir?",
    "{term} ne anlama gelir?",
    "{term} nasıl tanımlanır?",
    "{term} nasıl açıklanır?",
    "{term} kavramı nedir?",
    "{term} terimi nedir?"
)

$genericFocusTemplatesEn = @(
    "Which reading of {term} is most reliable?",
    "When does {term} become important?",
    "Which explanation of {term} is the best fit?",
    "What practical result can {term} explain?",
    "Which fact about {term} avoids a wrong reading?",
    "Which relation helps explain {term}?",
    "Which example makes {term} clearer?",
    "Why can {term} matter in practice?",
    "Which detail makes {term} easier to understand?",
    "Which option gives the safer interpretation of {term}?"
)

function Get-Templates($lang, $categoryKey) {
    if ($lang -eq "tr" -and $categoryKey -eq "spor") {
        return Get-SportQuestionTemplates "{definition}"
    }
    $generated = Get-GeneratedTemplates $lang
    $blocked = "Bu kavram|Bu bilgi|Bu açıklama|Tanım:|Açıklama:|İpucu:|Bilgi:|Kısa tanım:|Net ipucu:|Temel açıklama:|Doğrudan bilgi:|Soru:|Özet:|Öğrenme notu:|SadeBil|quiz|Sade anlat|sade anlat|Temel bilgi olarak|Kısaca bakınca|En genel|denilince|servis denilince|neyi ifade eder|neyi anlatır|neyi açıklar|neyi gösterir|hangi yorum|doğru yorum|konusunda doğru|sade ve doğru|Definition:|Explanation:|Clue:|Fact:|Short definition:|Direct clue:|Summary:|Learning note:|In simple terms|In plain language|As a core idea|At the basic level|This concept|This fact|This explanation"
    return @($generated | Where-Object { $_ -notmatch $blocked } | Select-Object -Unique | Select-Object -First 240)
}

function Get-GeneratedTemplates($lang) {
    return Get-DirectQuestionTemplates $lang "{definition}"
}

$factOpenersTr = @(
    "{term}: {fact}",
    "Kısa bilgi: {fact}",
    "Akılda kalsın: {fact}",
    "Sade anlatım: {fact}",
    "Bu soru şunu ölçer: {fact}",
    "Temel nokta: {fact}",
    "Yanılmamak için: {fact}",
    "Özetle: {fact}"
)

$factOpenersEn = @(
    "{term}: {fact}",
    "Quick note: {fact}",
    "Remember this: {fact}",
    "Simple view: {fact}",
    "This question checks: {fact}",
    "Core point: {fact}",
    "To avoid mistakes: {fact}",
    "In short: {fact}"
)

$wrongTrByCategory = @{
    ekonomi = @(
        "fiyat seviyesini", "vergi oranını", "kâr payını", "borç vadesini",
        "nakit akışını", "arz miktarını", "talep miktarını", "kur seviyesini",
        "bütçe dengesini", "faiz oranını", "ödeme gücünü", "gelir dağılımını",
        "üretim hacmini", "tasarruf eğilimini", "yatırım riskini", "maliyet baskısını",
        "piyasa sepetini", "dış ticareti", "kredi koşulunu", "para talebini",
        "getiri beklentisini", "harcama gücünü", "ithalat maliyetini", "finansman açığını"
    )
    bilim = @(
        "enerji dönüşümünü", "hücre bölünmesini", "kütle ölçümünü", "ışık yayılımını",
        "canlı uyumunu", "basınç etkisini", "madde yapısını", "gen aktarımını",
        "ısı değişimini", "ses iletimini", "kimyasal bağı", "mikrop türünü",
        "sinir iletimini", "gezegen hareketini", "bağışıklık yanıtını", "yoğunluk farkını",
        "ekosistem dengesini", "elektrik yükünü", "kalıtsal bilgiyi", "dalgaların hızını",
        "sıcaklık ölçümünü", "karbon dolaşımını", "nöron bağlantısını", "uzay uzaklığını"
    )
    teknoloji = @(
        "veri aktarımını", "güvenlik katmanını", "sunucu isteğini", "şifre korumasını",
        "ağ bağlantısını", "dosya yedeğini", "erişim iznini", "kimlik doğrulamayı",
        "veri deposunu", "işlem hızını", "geçici belleği", "sistem güncellemesini",
        "konum bilgisini", "kablosuz bağlantıyı", "yazılım arayüzünü", "zararlı kodu",
        "site oturumunu", "cihaz eşleşmesini", "bulut hizmetini", "yapay tahmin",
        "algoritma adımını", "gizlilik ayarını", "açık kod", "ödeme temasını"
    )
    sanat = @(
        "görsel düzeni", "renk uyumunu", "derinlik hissini", "duygu yönünü",
        "sahne akışını", "hikaye planını", "karakter değişimini", "ses uyumunu",
        "kadraj seçimini", "vurgu gücünü", "tekrar akışını", "yazı tasarımını",
        "ana düşünceyi", "anlatıcı sesini", "kamera bakışını", "ezgi çizgisini",
        "eser korumasını", "marka işaretini", "dolaylı anlamı", "gerçek anlatıyı",
        "kurmaca dünyayı", "biçim etkisini", "ışık yönünü", "tempo hissini"
    )
    spor = @(
        "oyun planını", "saha yerleşimini", "hızlı çıkışı", "savunma baskısını",
        "sayı pasını", "uzak şut ödülünü", "top paylaşımını", "seken topu almayı",
        "fizik hazırlığı", "kalp dayanıklılığını", "yüklenme hazırlığını", "hareket açıklığını",
        "yenilenme sürecini", "saygılı rekabeti", "video incelemeyi", "eleme aşamasını",
        "kısa hızlı koşuyu", "uzun dayanıklılığı", "sıvı dengesini", "risk azaltmayı",
        "tempo kontrolünü", "antrenman yükünü", "takım iletişimini", "maç stratejisini"
    )
    muzik = @(
        "ritim akışını", "melodi çizgisini", "armoni uyumunu", "sahne yorumunu",
        "ses rengini", "tempo hissini", "enstrüman rolünü", "vokal tekniğini",
        "albüm bütünlüğünü", "konser performansını", "müzik akımını", "şarkı yapısını",
        "nakarat etkisini", "beste fikrini", "aranje düzenini", "doğaçlama alanını",
        "kayıt kalitesini", "prodüksiyon tarzını", "dinleyici duygusunu", "kültürel etkiyi",
        "sanatçı yorumunu", "tür ayrımını", "sahne enerjisini", "müzik tarihini"
    )
    tarih = @(
        "dönem bağlamını", "siyasi sonucu", "toplumsal değişimi", "kültürel mirası",
        "lider etkisini", "savaş nedenini", "antlaşma sonucunu", "göç hareketini",
        "devlet düzenini", "reform amacını", "ticaret yolunu", "keşif etkisini",
        "imparatorluk yapısını", "bağımsızlık fikrini", "anayasal süreci", "diplomasi dilini",
        "tarihsel kaynağı", "medeniyet katkısını", "ekonomik dönüşümü", "askeri stratejiyi",
        "çağ değişimini", "devrim sonucunu", "figür rolünü", "olay zincirini"
    )
    guncel = @(
        "kaynak güvenini", "zaman bağlamını", "yanlış bilgi yayılımını", "kişisel korumayı",
        "küçük ödemeleri", "kaynak dengesini", "doğru bilgi akışını", "önceden plan",
        "kent yoğunluğunu", "mekan esnekliğini", "sorumlu kullanımı", "çevrimiçi izleri",
        "özel alan hakkını", "toplum algısını", "hızlı ilgiyi", "dar bilgi çevresini",
        "kanıt aramayı", "daha az tüketimi", "kaynak korumayı", "yenebilir kaybı",
        "salım etkisini", "alıcı korumasını", "haberi çözümlemeyi", "zaman rekabetini"
    )
}

$wrongEnByCategory = @{
    ekonomi = @(
        "price level", "tax rate", "profit share", "debt maturity",
        "cash flow", "supply amount", "demand amount", "currency level",
        "budget balance", "interest rate", "payment strength", "income spread",
        "output volume", "saving tendency", "investment risk", "cost pressure",
        "market basket", "foreign trade", "loan condition", "money demand",
        "return expectation", "spending power", "import cost", "funding gap"
    )
    bilim = @(
        "energy change", "cell division", "mass measure", "light spread",
        "living adaptation", "pressure effect", "matter structure", "gene transfer",
        "heat change", "sound transfer", "chemical bond", "microbe type",
        "nerve signaling", "planet motion", "immune response", "density difference",
        "ecosystem balance", "electric charge", "genetic information", "wave speed",
        "temperature measure", "carbon movement", "neuron connection", "space distance"
    )
    teknoloji = @(
        "data transfer", "security layer", "server request", "password protection",
        "network connection", "file backup", "access permission", "identity check",
        "data store", "processing speed", "temporary memory", "system update",
        "location data", "wireless link", "software interface", "harmful code",
        "site session", "device pairing", "cloud service", "AI prediction",
        "algorithm step", "privacy setting", "open code", "payment touch"
    )
    sanat = @(
        "visual order", "color harmony", "depth feeling", "emotion direction",
        "scene flow", "story plan", "character change", "sound agreement",
        "frame choice", "emphasis power", "repeated flow", "letter design",
        "main idea", "narrator voice", "camera view", "tune line",
        "art preservation", "brand mark", "indirect meaning", "real telling",
        "fiction world", "form effect", "light direction", "tempo feeling"
    )
    spor = @(
        "game plan", "field shape", "fast transition", "defensive pressure",
        "scoring pass", "long-shot reward", "ball sharing", "loose ball recovery",
        "physical readiness", "heart endurance", "load preparation", "range support",
        "renewal phase", "respectful play", "video review", "elimination stage",
        "short fast run", "long endurance", "fluid balance", "risk reduction",
        "pace control", "training load", "team communication", "match strategy"
    )
    muzik = @(
        "rhythm flow", "melody line", "harmony blend", "stage interpretation",
        "sound color", "tempo feeling", "instrument role", "vocal technique",
        "album unity", "concert performance", "music movement", "song structure",
        "chorus effect", "composition idea", "arrangement order", "improvisation space",
        "recording quality", "production style", "listener emotion", "cultural impact",
        "artist interpretation", "genre distinction", "stage energy", "music history"
    )
    tarih = @(
        "period context", "political outcome", "social change", "cultural heritage",
        "leader influence", "war cause", "treaty result", "migration movement",
        "state order", "reform purpose", "trade route", "discovery impact",
        "empire structure", "independence idea", "constitutional process", "diplomatic language",
        "historical source", "civilization contribution", "economic shift", "military strategy",
        "age transition", "revolution result", "figure role", "event chain"
    )
    guncel = @(
        "source trust", "time context", "false spread", "personal protection",
        "small payments", "resource balance", "verified flow", "advance planning",
        "city density", "location flexibility", "responsible use", "online traces",
        "private control", "social perception", "fast attention", "narrow info circle",
        "evidence check", "lower consumption", "resource care", "avoidable food loss",
        "emission impact", "buyer protection", "news interpretation", "time competition"
    )
}

$topicsTr = @{
    ekonomi = Parse-Topics @(
        "enflasyon|fiyat artış hızını|Enflasyon, genel fiyat düzeyinin ne kadar hızlı arttığını gösterir.",
        "dezenflasyon|artışın yavaşlamasını|Dezenflasyon fiyatların düşmesi değil, fiyat artış hızının azalmasıdır.",
        "deflasyon|fiyat düşüşünü|Deflasyon genel fiyat düzeyinin gerilemesi ve talebin zayıflamasıyla ilgilidir.",
        "politika faizi|para maliyetini|Merkez bankasının faizi, kredi ve mevduat maliyetini etkileyen ana sinyaldir.",
        "reel faiz|enflasyon sonrası getiriyi|Reel faiz, nominal getirinin enflasyon etkisinden arındırılmış halidir.",
        "nominal faiz|görünen faizi|Nominal faiz, enflasyon düşülmeden açıklanan faiz oranıdır.",
        "döviz kuru|para değişim oranını|Döviz kuru, iki para biriminin birbirine göre değerini gösterir.",
        "kur geçişkenliği|maliyet aktarımını|Kur artışı ithal maliyetleri üzerinden ürün fiyatlarına yansıyabilir.",
        "cari açık|dış ödeme açığını|Cari açık, ülkenin döviz gelirinden fazla döviz gideri oluşmasıdır.",
        "bütçe açığı|kamu gelir açığını|Bütçe açığı, kamu harcamalarının kamu gelirlerini aşmasıdır.",
        "tahvil|borçlanma senedini|Tahvil, borç veren yatırımcıya belirli getiri vadeden bir araçtır.",
        "tahvil faizi|borcun getirisini|Tahvil faizi yükselirse eski tahvillerin piyasa fiyatı baskı görebilir.",
        "risk primi|güven maliyetini|Risk primi, yatırımcının belirsizlik için istediği ek getiriyi anlatır.",
        "kredi notu|geri ödeme güvenini|Kredi notu, borçlunun borcunu ödeme kabiliyetine dair algıyı gösterir.",
        "resesyon|ekonomik daralmayı|Resesyon, üretim ve harcamalarda belirgin yavaşlama dönemidir.",
        "büyüme|üretim artışını|Ekonomik büyüme, mal ve hizmet üretimindeki artışla ölçülür.",
        "işsizlik|çalışma boşluğunu|İşsizlik, çalışmak isteyenlerin iş bulamaması durumudur.",
        "verimlilik|birim başı çıktıyı|Verimlilik, aynı kaynakla daha fazla üretim yapabilme gücüdür.",
        "arz|sunulan miktarı|Arz, üreticilerin belirli fiyatta piyasaya sunduğu miktardır.",
        "talep|satın alma isteğini|Talep, tüketicinin belirli fiyatta almak istediği miktarı anlatır.",
        "likidite|kolay nakde dönüşü|Likidite, bir varlığın değer kaybetmeden hızlıca nakde çevrilebilmesidir.",
        "mevduat|bankadaki birikimi|Mevduat, bankada tutulan ve faiz getirisi sağlayabilen paradır.",
        "borsa endeksi|piyasa sepetini|Endeks, seçili hisselerin genel performansını özetleyen göstergedir.",
        "temettü|kâr payını|Temettü, şirket kârının yatırımcıya dağıtılan bölümüdür.",
        "bilanço|mali tabloyu|Bilanço, şirketin varlık, borç ve özkaynak durumunu gösterir."
    )
    bilim = Parse-Topics @(
        "atom|maddenin yapı taşını|Atom, maddenin kimyasal özelliklerini taşıyan temel birimdir.",
        "molekül|atom bağını|Molekül, birden çok atomun kimyasal bağlarla bir araya gelmesidir.",
        "DNA|genetik bilgiyi|DNA, canlıların kalıtsal bilgisini taşıyan moleküldür.",
        "RNA|protein mesajını|RNA, genetik bilgiyi protein üretimine taşımada görev alır.",
        "hücre|yaşam birimini|Hücre, canlıların yapı ve işlev bakımından temel birimidir.",
        "fotosentez|ışıkla besin üretimini|Fotosentez, bitkilerin ışık enerjisiyle besin üretmesidir.",
        "evrim|nesiller arası değişimi|Evrim, canlı topluluklarının zamanla kalıtsal olarak değişmesidir.",
        "yerçekimi|kütle çekimini|Yerçekimi, kütlelerin birbirini çekmesiyle oluşan kuvvettir.",
        "elektromanyetizma|yük etkileşimini|Elektrik ve manyetizma aynı temel etkileşimin parçalarıdır.",
        "ışık yılı|uzaklık ölçüsünü|Işık yılı, ışığın bir yılda aldığı mesafeyi anlatan uzaklık birimidir.",
        "yıldız|ışık üreten gökcismini|Yıldızlar, çekirdek tepkimeleriyle ışık ve enerji üretir.",
        "gezegen|yörüngedeki gökcismini|Gezegen, yıldız çevresinde dolanan büyük gök cismidir.",
        "kara delik|aşırı çekimi|Kara delik, ışığın bile kaçamadığı çok güçlü çekim alanıdır.",
        "aşı|bağışıklık hazırlığını|Aşı, bağışıklık sistemini güvenli biçimde eğitir.",
        "antibiyotik|bakteri tedavisini|Antibiyotikler bakterilere karşı kullanılır, virüslere karşı doğrudan çalışmaz.",
        "virüs|hücreye bağımlı etkeni|Virüsler çoğalmak için canlı hücre mekanizmasına ihtiyaç duyar.",
        "bakteri|tek hücreli canlıyı|Bakteriler tek hücreli mikroorganizmalardır ve her biri zararlı değildir.",
        "iklim değişikliği|uzun dönem değişimi|İklim değişikliği, sıcaklık ve hava düzenlerindeki uzun vadeli kaymadır.",
        "karbon döngüsü|karbon dolaşımını|Karbon döngüsü, karbonun atmosfer, canlılar ve okyanuslar arasında taşınmasıdır.",
        "enerji korunumu|enerji sabitliğini|Enerji yoktan var olmaz, sadece biçim değiştirir.",
        "basınç|alan başı kuvveti|Basınç, kuvvetin yüzeye dağılımını gösterir.",
        "yoğunluk|hacim başı kütleyi|Yoğunluk, bir maddenin birim hacimdeki kütlesidir.",
        "sinaps|nöron bağlantısını|Sinaps, sinir hücrelerinin bilgi aktardığı bağlantı noktasıdır.",
        "hafıza|bilgi saklamayı|Hafıza, bilginin kodlanması, saklanması ve geri çağrılmasıdır.",
        "uyku|beyin toparlanmasını|Uyku, hafıza, dikkat ve beden onarımı için aktif bir süreçtir."
    )
    teknoloji = Parse-Topics @(
        "yapay zeka|örüntü öğrenmeyi|Yapay zeka, veriden örüntü öğrenip tahmin veya üretim yapar.",
        "makine öğrenmesi|veriden öğrenmeyi|Makine öğrenmesi, açık kural yazmadan örneklerden sonuç çıkarmadır.",
        "algoritma|adım planını|Algoritma, bir problemi çözmek için izlenen düzenli adımlardır.",
        "veri|işlenebilir bilgiyi|Veri, analiz ve karar için kullanılan ham veya düzenlenmiş bilgidir.",
        "bulut|uzak sunucuyu|Bulut, dosya ve hizmetlerin internet üzerindeki sunucularda çalışmasıdır.",
        "sunucu|hizmet veren sistemi|Sunucu, başka cihazlara veri veya hizmet sağlayan bilgisayardır.",
        "istemci|hizmet isteyen cihazı|İstemci, sunucudan veri veya hizmet talep eden cihaz ya da yazılımdır.",
        "şifreleme|veriyi gizlemeyi|Şifreleme, bilgiyi yetkisiz kişilerin okuyamayacağı forma dönüştürür.",
        "uçtan uca şifreleme|uç cihaz gizliliğini|Uçtan uca şifrelemede mesaj yalnızca alıcı ve göndericide okunur.",
        "iki faktörlü doğrulama|ikinci kanıtı|İki faktör, şifreye ek olarak başka bir doğrulama ister.",
        "siber güvenlik|dijital korumayı|Siber güvenlik, sistemleri ve verileri saldırılara karşı korur.",
        "oltalama|sahte kandırmayı|Oltalama, sahte mesaj veya siteyle bilgi çalmaya çalışır.",
        "kötü amaçlı yazılım|zararlı kodu|Zararlı yazılım cihazı bozabilir, veri çalabilir veya sistemi kilitleyebilir.",
        "güncelleme|açık kapatmayı|Güncellemeler güvenlik açıklarını kapatıp hataları düzeltebilir.",
        "yedekleme|veri kopyasını|Yedekleme, veri kaybına karşı ikinci bir kopya tutmaktır.",
        "QR kod|görsel veri taşımayı|QR kod, bağlantı veya kısa bilgiyi kare desenle taşır.",
        "robotik|algılayan makineyi|Robotik, sensör, yazılım ve mekanik hareketi birleştirir.",
        "Bluetooth|kısa mesafe bağlantıyı|Bluetooth, yakındaki cihazlar arasında düşük güçlü bağlantı kurar.",
        "Wi-Fi|kablosuz ağı|Wi-Fi, cihazların kablosuz yerel ağa bağlanmasını sağlar.",
        "GPS|konum belirlemeyi|GPS, uydulardan gelen sinyallerle konum tahmini yapar.",
        "biyoteknoloji|canlı sistem teknolojisini|Biyoteknoloji, canlı süreçleri sağlık, tarım veya üretim için kullanır.",
        "uzay teknolojisi|yörünge ve keşif araçlarını|Uzay teknolojisi uydu, roket ve gözlem sistemlerini kapsar.",
        "API|yazılım arayüzünü|API, iki yazılımın düzenli biçimde konuşmasını sağlayan arayüzdür.",
        "yenilenebilir enerji|temiz kaynak kullanımını|Güneş, rüzgar ve benzeri kaynaklar enerji teknolojisinin önemli parçasıdır.",
        "kuantum bilgisayar|olasılıksal işlem gücünü|Kuantum bilgisayarlar bazı problemlerde klasik bilgisayardan farklı hesaplama yolu kullanır."
    )
    sanat = Parse-Topics @(
        "kompozisyon|görsel düzeni|Kompozisyon, öğelerin kadraj veya yüzey içindeki düzenidir.",
        "perspektif|derinlik hissini|Perspektif, iki boyutlu yüzeyde uzaklık ve derinlik duygusu verir.",
        "kontrast|ayrım gücünü|Kontrast, öğeleri ayırt etmeyi ve vurguyu artırır.",
        "renk paleti|renk uyumunu|Renk paleti, bir eserde kullanılan renklerin bilinçli seçimidir.",
        "minimalizm|azla anlatmayı|Minimalizm, gereksiz öğeleri azaltıp odağı güçlendirir.",
        "tipografi|yazı tasarımını|Tipografi, yazının okunabilirlik ve karakter taşıyan düzenidir.",
        "ışık|vurgu yönünü|Işık, sahnede dikkat ve duygu yönünü belirler.",
        "gölge|hacim etkisini|Gölge, formun ve mekânın derinliğini hissettirir.",
        "kadraj|seçili alanı|Kadraj, görüntüde neyin dahil edilip neyin dışarıda bırakıldığını gösterir.",
        "Rönesans sanatı|insan merkezli canlanmayı|Rönesans sanatı, insanı, doğayı ve perspektifi öne çıkaran dönüşümdür.",
        "Barok sanat|dramatik hareketi|Barok sanat, güçlü ışık, hareket ve duygusal yoğunlukla tanınır.",
        "empresyonizm|anlık izlenimi|Empresyonizm, ışığın ve anlık görsel izlenimin etkisini yakalamaya çalışır.",
        "kübizm|parçalı bakışı|Kübizm, nesneleri farklı açılardan parçalı biçimde gösterir.",
        "sürrealizm|bilinçdışı imgeleri|Sürrealizm, rüya ve bilinçdışı çağrışımları sanat diline taşır.",
        "ekspresyonizm|iç duygu vurgusunu|Ekspresyonizm, dış gerçeklikten çok iç duygu ve gerilimi öne çıkarır.",
        "heykel|üç boyutlu formu|Heykel, hacim, malzeme ve mekân ilişkisiyle kurulan sanattır.",
        "mimari|yaşam alanı sanatını|Mimari, işlev, estetik ve yapısal düşünceyi birleştirir.",
        "fresk|ıslak sıva resmini|Fresk, yaş sıva üzerine yapılan dayanıklı duvar resmidir.",
        "mozaik|parça düzenini|Mozaik, küçük taş, cam veya seramik parçalarla görüntü oluşturur.",
        "minyatür|ince detay resmini|Minyatür, küçük ölçekte yoğun ayrıntı ve anlatı taşıyan resim geleneğidir.",
        "hat sanatı|yazı estetiğini|Hat sanatı, yazıyı ölçü, ritim ve estetikle görsel değere dönüştürür.",
        "müze|eser koruma alanını|Müze, kültürel ve sanatsal mirası korur, araştırır ve sergiler.",
        "bienal|dönemsel sanat buluşmasını|Bienal, çağdaş sanatın belirli aralıklarla geniş sergilenmesidir.",
        "logo|marka işaretini|Logo, markanın hızlı tanınmasını sağlayan görsel işarettir.",
        "restorasyon|eseri korumayı|Restorasyon, kültürel eseri özgün yapısına saygıyla onarmaktır."
    )
    spor = Parse-Topics @(
        "ofsayt|zamanlama kuralını|Ofsayt, hücum oyuncusunun avantajlı bekleyişini sınırlayan kuraldır.",
        "pres|rakibe baskıyı|Pres, top rakipteyken hata yaptırmak için yapılan baskıdır.",
        "kontra atak|hızlı çıkışı|Kontra atak, top kazanılınca rakip yerleşmeden hücuma çıkmaktır.",
        "pas oyunu|top paylaşımını|Pas oyunu, takımın topu dolaştırarak alan ve fırsat bulmasıdır.",
        "üçlük|uzak şut ödülünü|Basketbolda üçlük, uzak mesafeden isabetli atışa verilen puandır.",
        "ribaund|seken topu almayı|Ribaund, kaçan şuttan sonra topu kazanma mücadelesidir.",
        "asist|sayı pasını|Asist, takım arkadaşının skor üretmesini sağlayan pastır.",
        "servis|oyunu başlatmayı|Servis, teniste veya voleybolda oyunu başlatan vuruştur.",
        "kondisyon|fizik hazırlığı|Kondisyon, sporcunun dayanıklılık ve hareket kapasitesidir.",
        "kardiyo|kalp dayanıklılığını|Kardiyo, kalp ve solunum sisteminin çalışma kapasitesini geliştirir.",
        "ısınma|yüklenmeye hazırlığı|Isınma, vücudu antrenman veya maç temposuna hazırlar.",
        "esneme|hareket açıklığını|Esneme, kas ve eklemlerin hareket aralığını destekler.",
        "toparlanma|yenilenme sürecini|Toparlanma, vücudun antrenman yüküne uyum sağladığı dönemdir.",
        "kas gelişimi|uyaran ve onarımı|Kas gelişimi, antrenman, beslenme ve dinlenmenin birlikte çalışmasıdır.",
        "interval|aralıklı tempoyu|Interval, yüksek ve düşük yoğunluklu bölümlerin sırayla yapılmasıdır.",
        "taktik|oyun planını|Taktik, rakibe ve duruma göre belirlenen oyun planıdır.",
        "diziliş|saha yerleşimini|Diziliş, oyuncuların sahadaki başlangıç ve görev yerleşimini gösterir.",
        "fair play|saygılı rekabeti|Fair play, kurallara ve rakibe saygılı yarışma anlayışıdır.",
        "VAR|video incelemeyi|VAR, kritik hakem kararlarında video desteği sağlayan sistemdir.",
        "playoff|eleme aşamasını|Playoff, sezon sonunda şampiyonluk veya yükselme için oynanan eleme bölümüdür.",
        "sprint|kısa hızlı koşuyu|Sprint, kısa mesafede maksimum hıza yakın koşudur.",
        "maraton|uzun dayanıklılığı|Maraton, uzun mesafede tempo ve dayanıklılık gerektiren koşudur.",
        "nabız|kalp atım hızını|Nabız, antrenman şiddetini takip etmek için kullanılan göstergedir.",
        "hidrasyon|sıvı dengesini|Hidrasyon, performans ve sağlık için yeterli sıvı dengesidir.",
        "sakatlık önleme|risk azaltmayı|Sakatlık önleme, yüklenme, teknik ve toparlanmayı dengede tutmaktır.",
        "korner|köşe vuruşunu|Korner, top savunmadan kale çizgisini geçince hücum takımının köşeden kullandığı vuruştur.",
        "penaltı|ceza vuruşunu|Penaltı, ceza alanındaki bazı ihlallerden sonra kaleye yakın noktadan kullanılan vuruştur.",
        "taç atışı|kenardan oyuna sokmayı|Taç atışı, top yan çizgiyi geçince oyunu yeniden başlatır.",
        "faul|kural dışı müdahaleyi|Faul, rakibe kurallar dışında yapılan müdahaledir.",
        "sarı kart|resmi uyarıyı|Sarı kart, futbol gibi sporlarda oyuncuya verilen resmi uyarıdır.",
        "kırmızı kart|oyundan ihraç kararını|Kırmızı kart, oyuncunun oyundan çıkarılması anlamına gelir.",
        "hakem|oyun yönetimini|Hakem, kuralları uygular ve maç içindeki kararları verir.",
        "kaleci|kaleyi korumayı|Kaleci, takımın kalesini koruyan özel görevli oyuncudur.",
        "forvet|hücum oyuncusunu|Forvet, takımın gol üretmesinde öne çıkan hücum oyuncusudur.",
        "orta saha|bağlantı bölgesini|Orta saha, savunma ile hücum arasındaki oyun bağlantısını kurar.",
        "savunma|rakibi durdurmayı|Savunma, rakibin sayı veya gol üretmesini engellemeye çalışır.",
        "şut|kaleye ya da potaya atışı|Şut, sayı veya gol amacıyla yapılan vuruş ya da atıştır.",
        "dripling|top sürmeyi|Dripling, oyuncunun topu kontrol ederek ilerletmesidir.",
        "smaç|sert hücum vuruşunu|Smaç, voleybolda veya basketbolda güçlü bitiriş hareketidir.",
        "blok|rakip hamleyi durdurmayı|Blok, rakibin atışını veya vuruşunu engellemeye çalışır.",
        "turnike|potaya yakın bitirişi|Turnike, basketbolda potaya yakın adımlarla yapılan atıştır.",
        "serbest atış|faul sonrası atışı|Serbest atış, basketbolda faul sonrası çizgiden kullanılan atıştır.",
        "pota|basketbol hedefini|Pota, basketbolda topun içinden geçirilmek istendiği hedeftir.",
        "periyot|oyun bölümünü|Periyot, basketbol gibi sporlarda maçın zaman dilimlerinden biridir.",
        "set|voleybol ve teniste bölüm kazanmayı|Set, bazı sporlarda oyunun ana bölümlerinden biridir.",
        "tie-break|eşitlik kırma oyununu|Tie-break, teniste seti sonuçlandırmak için oynanan özel bölümdür.",
        "ace|karşılanamayan servisi|Ace, servisin rakip tarafından karşılanamamasıyla alınan sayıdır.",
        "backhand|ters el vuruşunu|Backhand, raketin vücudun ters tarafından savrulduğu vuruştur.",
        "forehand|ön el vuruşunu|Forehand, raketin güçlü taraftan savrulduğu temel vuruştur.",
        "deuce|teniste eşitliği|Deuce, teniste iki tarafın oyunu kazanmak için üst üste puan aradığı eşitlik durumudur.",
        "file|oyun alanını ayırmayı|File, tenis ve voleybolda iki tarafı ayıran ağdır.",
        "libero|savunma uzmanını|Libero, voleybolda savunma ve karşılama görevinde öne çıkan oyuncudur.",
        "manşet|voleybol karşılama vuruşunu|Manşet, voleybolda topu ön kollarla kontrol etme vuruşudur.",
        "pasör|oyun kurucuyu|Pasör, voleybolda hücum organizasyonunu kuran oyuncudur.",
        "ralli|topun oyunda kalma sürecini|Ralli, topun iki taraf arasında oyunda kaldığı bölümdür.",
        "nakavt|boks maçını bitiren üstünlüğü|Nakavt, boksörün mücadeleye devam edemeyecek duruma gelmesidir.",
        "raunt|boks bölümü|Raunt, boks ve dövüş sporlarında maçın zaman dilimidir.",
        "gard|savunma duruşunu|Gard, boks ve dövüş sporlarında korunma duruşudur.",
        "jab|kısa direkt yumruğu|Jab, boksun hızlı ve kısa direkt yumruğudur.",
        "kroşe|yandan yumruğu|Kroşe, yandan kavisli şekilde atılan yumruktur.",
        "tekme savunması|vuruşu karşılamayı|Tekme savunması, dövüş sporlarında gelen tekmeyi etkisizleştirmeye çalışır.",
        "tuş|güreşte omuzları yere bastırmayı|Tuş, güreşte rakibin iki omzunu minderle temas ettirmektir.",
        "minder|güreş alanını|Minder, güreş ve bazı dövüş sporlarının yapıldığı yumuşak alandır.",
        "ippon|judoda tam puanı|Ippon, judoda karşılaşmayı bitirebilen tam puandır.",
        "tatami|judo alanını|Tatami, judo ve bazı dövüş sporlarında kullanılan minder alanıdır.",
        "halter|ağırlık kaldırmayı|Halter, sporcunun belirli kurallarla ağırlık kaldırdığı spordur.",
        "koparma|halter kaldırışını|Koparma, halterde ağırlığın tek harekette baş üstüne alınmasıdır.",
        "silkme|halterde iki aşamalı kaldırışı|Silkme, halterde ağırlığın omuza alınıp sonra baş üstüne kaldırılmasıdır.",
        "kulvar|yarış şeridini|Kulvar, atletizm ve yüzmede sporcunun yarıştığı şerittir.",
        "bayrak yarışı|takım koşusunu|Bayrak yarışı, sporcuların sırayla koşup bayrak devrettiği takım yarışıdır.",
        "uzun atlama|mesafe atlayışını|Uzun atlama, sporcunun koşu sonrası en uzağa atlamaya çalıştığı branştır.",
        "yüksek atlama|yükseklik geçişini|Yüksek atlama, sporcunun çıtayı düşürmeden geçmeye çalıştığı branştır.",
        "gülle atma|ağırlık fırlatmayı|Gülle atma, ağır metal kürenin en uzağa gönderilmeye çalışıldığı branştır.",
        "disk atma|disk fırlatmayı|Disk atma, diskin belirli alandan en uzağa atılmasıdır.",
        "cirit atma|mızrak benzeri aracı fırlatmayı|Cirit atma, ciridin en uzağa gönderildiği atletizm branşıdır.",
        "engelli koşu|engel aşarak koşmayı|Engelli koşu, belirli aralıklarla konan engelleri aşarak yapılan koşudur.",
        "kelebek stil|yüzme tekniğini|Kelebek stil, iki kolun aynı anda ileri taşındığı zorlu yüzme tekniğidir.",
        "kurbağalama|yüzme stilini|Kurbağalama, kollar ve bacakların simetrik hareket ettiği yüzme stilidir.",
        "serbest stil|hızlı yüzme stilini|Serbest stil, yüzmede genellikle kulaç tekniğiyle yapılan hızlı stildir.",
        "sırtüstü|sırt üzerinde yüzmeyi|Sırtüstü, sporcunun sırtı suya dönük şekilde yüzdüğü stildir.",
        "kulaç|yüzme kol hareketini|Kulaç, yüzmede kollarla yapılan ilerletici harekettir.",
        "dalış|suya kontrollü atlamayı|Dalış, belirli teknikle suya girme veya su altında ilerleme eylemidir.",
        "bisiklet pelotonu|yarışçı grubunu|Peloton, bisiklet yarışlarında ana sporcu grubudur.",
        "etap|yarış bölümü|Etap, bisiklet gibi yarışlarda parkurun ayrı bölümüdür.",
        "pit stop|yarış servis molasını|Pit stop, motor sporlarında aracın kısa süreli servis için durmasıdır.",
        "pole pozisyonu|ilk start yerini|Pole pozisyonu, yarışa en önden başlama hakkıdır.",
        "tur zamanı|bir pist turu süresini|Tur zamanı, sporcunun veya aracın bir turu tamamlama süresidir.",
        "karting|küçük yarış aracı sporunu|Karting, küçük motorlu araçlarla yapılan pist yarışıdır.",
        "kayak|kar üzerinde kaymayı|Kayak, kar üzerinde özel ekipmanla yapılan spordur.",
        "slalom|kapılar arasından kaymayı|Slalom, kayakta belirli kapılar arasından geçilerek yapılan yarıştır.",
        "snowboard|tek tahta ile kaymayı|Snowboard, kar üzerinde tek geniş tahta ile yapılan spordur.",
        "paten|buz veya zeminde kaymayı|Paten, tekerlekli ya da buz bıçaklı ayakkabıyla yapılan spordur.",
        "artistik patinaj|buz üstü estetik performansı|Artistik patinaj, buz üzerinde teknik ve estetik hareketleri birleştirir.",
        "curling|buz üzerinde taş yönlendirmeyi|Curling, buz üstünde taşları hedefe yaklaştırmaya dayanan spordur.",
        "beyzbol|sopa ve top oyununu|Beyzbol, sopayla topa vurup koşu tamamlamaya dayanan takım sporudur.",
        "kriket|sopa ve wicket oyununu|Kriket, sopayla topa vurma ve wicket koruma üzerine kurulu spordur.",
        "ragbi|temaslı takım oyununu|Ragbi, oval top ve fiziksel mücadeleyle oynanan takım sporudur.",
        "Amerikan futbolu|oval topla alan kazanmayı|Amerikan futbolu, alan kazanma ve touchdown hedefiyle oynanır.",
        "touchdown|Amerikan futbolu skorunu|Touchdown, topun rakip sayı alanına taşınmasıyla kazanılan skordur.",
        "golf|topu deliğe göndermeyi|Golf, topu sopayla en az vuruşla deliğe göndermeye dayanır.",
        "birdie|golfte iyi skoru|Birdie, golfte çukuru standart vuruş sayısından bir eksikle bitirmektir.",
        "par|golf standart vuruşunu|Par, golfte bir çukur için beklenen standart vuruş sayısıdır.",
        "bowling|lobut devirmeyi|Bowling, top ile lobutları devirmeye dayanan spordur.",
        "strike|bowlingde tüm lobutları devirmeyi|Strike, bowlingde ilk atışta tüm lobutların devrilmesidir.",
        "satranç matı|şahın kaçamamasını|Mat, satrançta şahın tehditten kurtulamadığı durumdur.",
        "rok|satrançta kale-şah hamlesini|Rok, satrançta şah ve kalenin özel güvenlik hamlesidir.",
        "piyon terfisi|piyonun taş değişimini|Piyon terfisi, piyonun son yataya ulaşınca güçlü taşa dönüşmesidir.",
        "okçuluk|yay ve okla hedef vurmayı|Okçuluk, yay ve ok kullanarak hedefi vurmaya dayanan spordur.",
        "yay|oku gönderen aracı|Yay, okçulukta okun hedefe gönderilmesini sağlayan araçtır.",
        "hedef tahtası|okçuluk hedefini|Hedef tahtası, okçulukta okun isabet ettirilmeye çalışıldığı bölümdür.",
        "eskrim|kılıçla puan mücadelesini|Eskrim, özel kılıçlarla puan almaya dayanan spordur.",
        "lunge|eskrimde hamle adımını|Lunge, eskrimde rakibe doğru yapılan temel saldırı adımıdır.",
        "badminton|raketle tüytop oyununu|Badminton, tüytopun raketle file üzerinden gönderildiği spordur.",
        "masa tenisi|küçük raket ve top oyununu|Masa tenisi, küçük topun masada file üzerinden oynandığı spordur.",
        "hentbol|elle oynanan takım sporunu|Hentbol, topun elle taşınıp kaleye atıldığı takım sporudur.",
        "sutopu|havuzda takım oyununu|Sutopu, havuzda yüzerek topu kaleye atmaya dayanan spordur.",
        "kürek|tekne ilerletmeyi|Kürek, sporcunun kürekle tekneyi ilerlettiği su sporudur.",
        "yelken|rüzgarla ilerlemeyi|Yelken, rüzgar gücünü kullanarak tekneyi yönlendirme sporudur.",
        "tırmanış|duvar ya da kaya çıkışını|Tırmanış, el ve ayak tutamaklarıyla yukarı ilerlemeye dayanır.",
        "parkur|engel aşma hareketini|Parkur, çevredeki engelleri akıcı hareketlerle aşmaya dayanan spordur.",
        "triathlon|üç branşlı dayanıklılığı|Triathlon yüzme, bisiklet ve koşuyu birleştiren dayanıklılık yarışıdır.",
        "pentatlon|beş branşlı yarışmayı|Modern pentatlon farklı becerileri bir araya getiren çoklu branş yarışıdır.",
        "dekathlon|on branşlı atletizmi|Dekathlon, erkeklerde on atletizm branşının toplamından oluşur.",
        "heptathlon|yedi branşlı atletizmi|Heptathlon, yedi atletizm branşını birleştiren yarışmadır.",
        "doping|yasaklı performans desteğini|Doping, sporda yasaklı madde veya yöntemle avantaj sağlamaktır.",
        "anti-doping|yasaklı madde denetimini|Anti-doping, sporda adil yarış için yasaklı maddeleri denetler.",
        "lisanslı sporcu|resmi kayıtlı sporcuyu|Lisanslı sporcu, federasyon veya ilgili kurumda resmi kaydı bulunan sporcudur.",
        "antrenör|sporcu hazırlığını yöneten kişiyi|Antrenör, sporcunun çalışma planını ve gelişimini yönlendirir.",
        "kaptan|takım liderini|Kaptan, sahada takımı temsil eden ve yönlendiren oyuncudur.",
        "yedek oyuncu|sonradan oyuna girebilecek oyuncuyu|Yedek oyuncu, maç içinde ihtiyaç olursa oyuna alınabilir.",
        "skor tabelası|maç sonucunu göstermeyi|Skor tabelası, maçtaki sayı veya gol durumunu gösterir.",
        "averaj|puan eşitliğinde fark hesabını|Averaj, takımlar puan eşitliğindeyken gol veya sayı farkını gösterir.",
        "lig|sezonluk yarış düzenini|Lig, takımların sezon boyunca belirli düzende karşılaştığı organizasyondur.",
        "turnuva|eleme veya grup yarışmasını|Turnuva, takımların veya sporcuların belirli formatta yarıştığı organizasyondur."
    )
    muzik = Parse-Topics @(
        "ritim|zaman akışını|Ritim, seslerin zaman içinde düzenli veya anlamlı yerleşmesidir.",
        "melodi|ana ezgiyi|Melodi, dinleyenin takip ettiği ana ses çizgisidir.",
        "armoni|ses uyumunu|Armoni, farklı seslerin birlikte uyumlu duyulmasıdır.",
        "tempo|hız duygusunu|Tempo, müziğin ne kadar hızlı veya yavaş aktığını gösterir.",
        "vokal|insan sesini|Vokal, şarkıda insan sesinin yorum ve duygu taşıyan bölümüdür.",
        "enstrüman|ses aracını|Enstrüman, müzik üretmek için kullanılan araçtır.",
        "orkestrasyon|çalgı dağılımını|Orkestrasyon, hangi çalgının ne zaman ve nasıl duyulacağını planlar.",
        "doğaçlama|anlık üretimi|Doğaçlama, müzisyenin o anda yeni müzikal fikir üretmesidir.",
        "caz|özgür yorum geleneğini|Caz, doğaçlama ve ritmik esneklikle öne çıkan bir müzik geleneğidir.",
        "klasik müzik|yazılı gelenek gücünü|Klasik müzikte beste, nota ve yorum ilişkisi güçlüdür.",
        "rock|gitar merkezli enerjiyi|Rock, elektrik gitar, güçlü ritim ve sahne enerjisiyle tanınır.",
        "pop|geniş kitle ezgisini|Pop müzik, akılda kalan yapı ve geniş dinleyiciye ulaşma amacı taşır.",
        "rap|ritmik söz anlatımını|Rap, ritim üzerinde söz, vurgu ve akışla kurulan anlatımdır.",
        "türkü|halk hafızasını|Türküler, toplumun duygu, olay ve yaşam deneyimini müzikle taşır.",
        "makam|ezgi karakterini|Makam, Türk müziğinde melodinin duygu ve seyir karakterini belirler.",
        "nota|ses yazısını|Nota, seslerin yükseklik ve süre bilgisini yazıyla gösterir.",
        "akor|aynı anda sesleri|Akor, birden fazla sesin birlikte duyulmasıyla oluşur.",
        "albüm|şarkı bütününü|Albüm, bir sanatçının belirli dönemdeki şarkılarını bütün halinde sunar.",
        "konser|canlı performansı|Konser, sanatçı ile dinleyici arasında canlı müzik deneyimi kurar.",
        "prodüktör|kayıt yönünü|Prodüktör, şarkının ses, düzenleme ve kayıt kimliğini şekillendirebilir.",
        "mastering|son ses ayarını|Mastering, kaydın farklı sistemlerde dengeli duyulması için yapılan son işlemdir.",
        "sampling|ses alıntısını|Sampling, var olan bir ses parçasını yeni üretimde kullanma tekniğidir.",
        "cover|yeniden yorumu|Cover, bilinen bir şarkının başka sanatçı tarafından yeniden yorumlanmasıdır.",
        "beste|özgün müzik fikrini|Beste, melodik ve yapısal müzik fikrinin oluşturulmasıdır.",
        "koro|toplu sesi|Koro, birden fazla sesin birlikte düzenli biçimde şarkı söylemesidir."
    )
    tarih = Parse-Topics @(
        "kronoloji|zaman sırasını|Kronoloji, olayları oluş sırasına göre anlamayı sağlar.",
        "uygarlık|kurumsal yaşamı|Uygarlık, şehir, yazı, hukuk ve kültür gibi gelişmiş yapıları içerir.",
        "imparatorluk|çok uluslu egemenliği|İmparatorluk, geniş toprak ve farklı toplulukları yöneten siyasi yapıdır.",
        "cumhuriyet|halk egemenliğini|Cumhuriyet, yönetim meşruiyetinin halk iradesine dayandığı sistemdir.",
        "devrim|köklü değişimi|Devrim, siyasi veya toplumsal düzeni hızlı ve köklü biçimde değiştirir.",
        "reform|düzenli yenilemeyi|Reform, sistemi yıkmadan iyileştirme ve yenileme girişimidir.",
        "Rönesans|yeniden doğuşu|Rönesans, Avrupa'da sanat, bilim ve düşüncede canlanma dönemidir.",
        "Sanayi Devrimi|makineleşme dönüşümünü|Sanayi Devrimi, üretimin makine ve fabrika düzenine geçişidir.",
        "Coğrafi Keşifler|dünya bağlantısını|Coğrafi Keşifler ticaret, sömürgecilik ve kültürel etkileşimi büyüttü.",
        "göç|yer değiştirmeyi|Göç, insanların ekonomik, siyasi veya güvenlik nedenleriyle yer değiştirmesidir.",
        "antlaşma|resmi uzlaşmayı|Antlaşma, tarafların savaş, sınır veya haklar konusunda yazılı uzlaşmasıdır.",
        "diplomasi|müzakere yolunu|Diplomasi, devletler arası sorunların görüşme ve temsil yoluyla yürütülmesidir.",
        "bağımsızlık|egemen karar hakkını|Bağımsızlık, bir toplumun kendi siyasi kararlarını dış baskı olmadan almasıdır.",
        "anayasa|temel hukuk düzenini|Anayasa, devletin işleyişini ve temel hakları belirleyen üst hukuk metnidir.",
        "arkeoloji|maddi kalıntı incelemesini|Arkeoloji, geçmiş toplumları kalıntılar üzerinden anlamaya çalışır.",
        "hiyeroglif|resimli yazıyı|Hiyeroglif, özellikle Eski Mısır'la özdeşleşen resimli yazı sistemidir.",
        "İpek Yolu|ticaret ağını|İpek Yolu, Asya ile Avrupa arasında mal ve kültür aktarımını sağlayan yollardır.",
        "Roma hukuku|hukuk mirasını|Roma hukuku, birçok modern hukuk sistemini etkileyen önemli bir mirastır.",
        "Osmanlı|çok kültürlü imparatorluğu|Osmanlı, yüzyıllar boyunca üç kıtada etkili olmuş bir imparatorluktur.",
        "Magna Carta|yetki sınırlamasını|Magna Carta, hükümdar yetkisinin hukukla sınırlanması fikrinde önemli görülür.",
        "Fransız İhtilali|eşitlik fikrini|Fransız İhtilali, vatandaşlık, eşitlik ve ulus düşüncesini güçlendirdi.",
        "Kurtuluş Savaşı|ulusal mücadeleyi|Kurtuluş Savaşı, bağımsızlık ve egemenlik mücadelesinin temel dönemidir.",
        "tarihsel kaynak|kanıt temelini|Tarihsel kaynaklar, geçmişi yorumlamak için kullanılan belge ve kalıntılardır."
    )
    guncel = Parse-Topics @(
        "dezenformasyon|yanlış bilgi yayılımını|Dezenformasyon, kasıtlı veya yönlendirici biçimde yanlış bilgi yayılmasıdır.",
        "kaynak kontrolü|kaynak güvenini|Kaynak kontrolü, bilginin kimden geldiğini ve güvenini sorgulamaktır.",
        "tarih kontrolü|haber zamanını|Eski bir haber yeniymiş gibi paylaşılırsa anlamı değişebilir.",
        "derin sahte|gerçekçi sahte medyayı|Derin sahte, yapay zeka ile üretilmiş inandırıcı sahte ses veya görüntüdür.",
        "veri güvenliği|kişisel veri korumasını|Veri güvenliği, kişisel bilgilerin izinsiz kullanımını önlemeye çalışır.",
        "abonelik ekonomisi|küçük ödemelerin birikmesini|Aboneliklerde küçük aylık ücretler toplamda ciddi masrafa dönüşebilir.",
        "sürdürülebilirlik|kaynak dengesini|Sürdürülebilirlik, bugünün ihtiyacını geleceği tüketmeden karşılamayı amaçlar.",
        "kriz iletişimi|doğru bilgi akışını|Kriz anında net ve doğrulanmış bilgi paniği azaltabilir.",
        "afet hazırlığı|önceden plan yapmayı|Afet hazırlığı, risk oluşmadan önce temel ihtiyaç ve iletişim planı yapmaktır.",
        "şehirleşme|kent yoğunluğunu|Şehirleşme, nüfus ve hizmetlerin kentlerde yoğunlaşmasıdır.",
        "uzaktan çalışma|mekan esnekliğini|Uzaktan çalışma, işin ofis dışından dijital araçlarla yürütülmesidir.",
        "yapay zeka etiği|sorumlu kullanımı|Yapay zeka etiği, adil, güvenli ve şeffaf kullanım sorularını ele alır.",
        "dijital ayak izi|çevrimiçi izleri|Dijital ayak izi, internette bıraktığımız veri ve davranış izleridir.",
        "mahremiyet|kişisel gizliliği|Mahremiyet, kişinin bilgilerinin kontrolünü elinde tutma hakkıdır.",
        "kamuoyu|toplum görüşünü|Kamuoyu, toplumun bir konu hakkındaki genel eğilimini anlatır.",
        "sosyal medya trendi|hızlı ilgiyi|Trend olmak, bir içeriğin kısa sürede yüksek görünürlük kazanmasıdır.",
        "algoritma balonu|dar bilgi çevresini|Algoritmalar benzer içerikleri göstererek farklı görüşleri azaltabilir.",
        "doğrulama|kanıt kontrolünü|Doğrulama, iddianın kaynağını ve kanıtını kontrol etmektir.",
        "enerji tasarrufu|daha az tüketimi|Enerji tasarrufu, aynı işi daha az enerjiyle yapmaya çalışmaktır.",
        "su tasarrufu|kaynak korumayı|Su tasarrufu, sınırlı su kaynaklarını bilinçli kullanmayı anlatır.",
        "gıda israfı|yenebilir yiyecek kaybını|Gıda israfı, tüketilebilecek yiyeceğin gereksiz yere çöpe gitmesidir.",
        "karbon ayak izi|salım etkisini|Karbon ayak izi, faaliyetlerin iklim üzerindeki emisyon etkisini gösterir.",
        "tüketici hakkı|alıcı korumasını|Tüketici hakkı, alışverişte bilgilendirme, iade ve güvenlik korumasıdır.",
        "medya okuryazarlığı|medya içeriğini okumayı|Medya okuryazarlığı, içeriğin kaynağını, amacını ve bağlamını okuyabilmektir.",
        "dikkat ekonomisi|zaman rekabetini|Dikkat ekonomisi, platformların kullanıcı ilgisi için yarışmasını anlatır."
    )
}

$topicsEn = @{
    ekonomi = Parse-Topics @(
        "inflation|price growth pace|Inflation shows how fast the general price level is rising.",
        "disinflation|slower price growth|Disinflation means prices rise more slowly, not that prices fall.",
        "deflation|falling prices|Deflation means the overall price level declines, often with weak demand.",
        "policy rate|money cost signal|A central bank rate influences loan and deposit costs.",
        "real rate|inflation-adjusted return|Real rate is the return after removing inflation's effect.",
        "nominal rate|stated interest rate|Nominal rate is the interest rate before adjusting for inflation.",
        "exchange rate|currency value ratio|Exchange rate shows the value of one currency against another.",
        "currency pass-through|cost transfer effect|A weaker currency can pass import costs into consumer prices.",
        "current account gap|external payment gap|A current account gap means foreign-currency outflows exceed inflows.",
        "budget deficit|public funding gap|A budget deficit happens when public spending exceeds public income.",
        "bond|debt security|A bond is a borrowing instrument that promises payments to investors.",
        "bond yield|debt return rate|When new yields rise, old lower-yield bonds can lose price.",
        "risk premium|uncertainty cost|Risk premium is extra return demanded for uncertainty.",
        "credit rating|repayment confidence|A credit rating reflects perceived ability to repay debt.",
        "recession|economic contraction|A recession is a period of weaker production and spending.",
        "growth|output increase|Economic growth is measured by higher production of goods and services.",
        "unemployment|job seeking gap|Unemployment means people want work but cannot find it.",
        "productivity|output per input|Productivity means producing more with the same resources.",
        "supply|offered quantity|Supply is how much producers offer at a given price.",
        "demand|buying willingness|Demand is how much consumers want to buy at a given price.",
        "liquidity|easy cash conversion|Liquidity is how quickly an asset can turn into cash without major loss.",
        "deposit|bank-held savings|A deposit is money kept at a bank, sometimes earning interest.",
        "stock index|market basket|An index summarizes the performance of selected stocks.",
        "dividend|profit share|A dividend is part of company profit paid to shareholders.",
        "balance sheet|financial snapshot|A balance sheet shows assets, liabilities and equity."
    )
    bilim = Parse-Topics @(
        "atom|matter building block|An atom is a basic unit carrying chemical properties of matter.",
        "molecule|bonded atoms|A molecule is atoms joined by chemical bonds.",
        "DNA|genetic information|DNA carries hereditary information in living things.",
        "RNA|protein message carrier|RNA helps carry genetic instructions into protein production.",
        "cell|basic life unit|The cell is the basic structural and functional unit of life.",
        "photosynthesis|light-based food making|Photosynthesis lets plants use light energy to make food.",
        "evolution|generation change|Evolution is inherited change in populations over time.",
        "gravity|mass attraction|Gravity is the attraction between masses.",
        "electromagnetism|charge interaction|Electricity and magnetism are parts of one fundamental interaction.",
        "light-year|distance measure|A light-year is the distance light travels in one year.",
        "star|light-producing body|Stars produce energy and light through nuclear reactions.",
        "planet|orbiting space body|A planet is a large body orbiting a star.",
        "black hole|extreme gravity|A black hole has gravity so strong that even light cannot escape.",
        "vaccine|immune preparation|A vaccine trains immunity in a safer way.",
        "antibiotic|bacteria treatment|Antibiotics fight bacteria, not viruses directly.",
        "virus|cell-dependent agent|Viruses need living cells to reproduce.",
        "bacteria|single-cell microbe|Bacteria are single-celled microbes, and many are not harmful.",
        "climate change|long-term shift|Climate change is a long-term shift in temperature and weather patterns.",
        "carbon cycle|carbon movement|The carbon cycle moves carbon through air, life and oceans.",
        "energy conservation|constant energy rule|Energy is not created or destroyed, only transformed.",
        "pressure|force per area|Pressure describes how force is spread over a surface.",
        "density|mass per volume|Density is mass packed into a unit of volume.",
        "synapse|neuron connection|A synapse is where nerve cells pass signals.",
        "memory|information storage|Memory involves encoding, storing and recalling information.",
        "sleep|brain recovery process|Sleep supports memory, attention and body repair."
    )
    teknoloji = Parse-Topics @(
        "artificial intelligence|pattern learning|AI learns patterns from data to predict or generate outputs.",
        "machine learning|learning from data|Machine learning finds patterns from examples without hand-written rules.",
        "algorithm|step plan|An algorithm is an ordered set of steps for solving a problem.",
        "data|usable information|Data is raw or organized information used for analysis and decisions.",
        "cloud computing|remote servers|Cloud services run storage or software on internet-based servers.",
        "server|service provider system|A server provides data or services to other devices.",
        "client|service requesting device|A client asks a server for data or service.",
        "encryption|data hiding method|Encryption turns information into a form outsiders cannot read.",
        "end-to-end encryption|device-only privacy|End-to-end encryption keeps messages readable only at the endpoints.",
        "two-factor authentication|second proof|Two-factor login asks for proof beyond a password.",
        "cybersecurity|digital protection|Cybersecurity protects systems and data from attacks.",
        "phishing|fake trust trick|Phishing uses fake messages or sites to steal information.",
        "malware|harmful code|Malware can steal data, damage devices or lock systems.",
        "software update|security fix|Updates can close security holes and fix bugs.",
        "backup|data copy|A backup is a second copy kept against data loss.",
        "QR code|visual data carrier|A QR code stores links or short data in a square pattern.",
        "robotics|sensing machine systems|Robotics combines sensors, software and mechanical movement.",
        "Bluetooth|short-range link|Bluetooth connects nearby devices with low-power radio.",
        "Wi-Fi|wireless network|Wi-Fi connects devices to a local wireless network.",
        "GPS|location estimate|GPS estimates location using satellite signals.",
        "biotechnology|living-system technology|Biotechnology uses living processes for health, agriculture or production.",
        "space technology|orbit and exploration tools|Space technology includes satellites, rockets and observation systems.",
        "API|software interface|An API lets two software systems communicate in a structured way.",
        "renewable energy|clean source use|Solar, wind and similar sources are key parts of energy technology.",
        "quantum computer|probabilistic computing power|Quantum computers use a different calculation path for some problems."
    )
    sanat = Parse-Topics @(
        "composition|visual arrangement|Composition is how elements are placed inside an image or surface.",
        "perspective|depth feeling|Perspective creates a sense of distance and depth on a flat surface.",
        "contrast|separation power|Contrast helps elements stand apart and gain emphasis.",
        "color palette|color harmony|A palette is the planned set of colors used in a work.",
        "minimalism|less with focus|Minimalism removes excess elements to strengthen focus.",
        "typography|letter design|Typography shapes readability and character through type.",
        "light|direction of attention|Light guides attention and mood in a scene.",
        "shadow|volume effect|Shadow helps show form, space and depth.",
        "framing|selected view|Framing decides what is included and excluded from the image.",
        "Renaissance art|human-centered revival|Renaissance art emphasized humans, nature and perspective.",
        "Baroque art|dramatic movement|Baroque art is known for strong light, motion and emotional intensity.",
        "impressionism|momentary impression|Impressionism tries to capture light and momentary visual effect.",
        "cubism|fragmented viewpoint|Cubism shows objects from multiple angles in broken forms.",
        "surrealism|unconscious imagery|Surrealism brings dream and unconscious associations into art.",
        "expressionism|inner feeling emphasis|Expressionism highlights inner emotion more than outer realism.",
        "sculpture|three-dimensional form|Sculpture builds art through volume, material and space.",
        "architecture|art of living space|Architecture combines function, beauty and structural thought.",
        "fresco|wet plaster painting|A fresco is a durable wall painting made on wet plaster.",
        "mosaic|piece arrangement|A mosaic creates an image from small stone, glass or ceramic pieces.",
        "miniature painting|fine-detail image|Miniature painting uses small scale with rich detail and narrative.",
        "calligraphy|writing aesthetics|Calligraphy turns writing into visual art through measure and rhythm.",
        "museum|art preservation space|A museum preserves, studies and displays cultural heritage.",
        "biennial|periodic art event|A biennial is a large recurring exhibition of contemporary art.",
        "logo|brand mark|A logo is a visual mark that helps a brand be recognized quickly.",
        "restoration|art preservation|Restoration repairs cultural works while respecting their original form."
    )
    spor = Parse-Topics @(
        "offside|timing rule|Offside limits an attacker's unfair waiting advantage.",
        "pressing|opponent pressure|Pressing tries to force errors when the opponent has the ball.",
        "counterattack|fast transition|A counterattack moves forward before the opponent is organized.",
        "passing play|ball sharing|Passing play moves the ball to create space and chances.",
        "three-pointer|long-shot reward|In basketball, a made long-range shot is worth three points.",
        "rebound|loose ball recovery|A rebound is winning the ball after a missed shot.",
        "assist|scoring pass|An assist is a pass that directly helps a teammate score.",
        "serve|play starter|A serve starts play in sports like tennis or volleyball.",
        "conditioning|physical readiness|Conditioning is the body's capacity for sustained effort.",
        "cardio|heart endurance|Cardio improves heart and breathing capacity.",
        "warm-up|load preparation|A warm-up prepares the body for training or match intensity.",
        "stretching|range support|Stretching supports muscle and joint range of motion.",
        "recovery|renewal phase|Recovery is when the body adapts to training load.",
        "muscle growth|stress and repair|Muscle growth needs training stimulus, food and rest.",
        "interval training|alternating pace|Intervals alternate high and low intensity sections.",
        "tactics|game plan|Tactics are plans adjusted to the opponent and situation.",
        "formation|field shape|Formation shows the team's starting positions and roles.",
        "fair play|respectful competition|Fair play means competing with respect for rules and rivals.",
        "VAR|video review|VAR supports referees on critical decisions through video checks.",
        "playoff|elimination stage|Playoffs are end-stage contests for titles or promotion.",
        "sprint|short fast run|A sprint is a short run close to maximum speed.",
        "marathon|long endurance race|A marathon requires pacing and endurance over a long distance.",
        "heart rate|beat frequency|Heart rate helps track exercise intensity.",
        "hydration|fluid balance|Hydration supports performance and health through fluid balance.",
        "injury prevention|risk reduction|Injury prevention balances load, technique and recovery."
    )
    muzik = Parse-Topics @(
        "rhythm|time flow|Rhythm places sounds meaningfully across time.",
        "melody|main tune|Melody is the main line of notes listeners follow.",
        "harmony|sound agreement|Harmony is the way different notes work together.",
        "tempo|speed feeling|Tempo shows how fast or slow the music moves.",
        "vocal|human voice|Vocal parts carry words, emotion and interpretation through voice.",
        "instrument|sound tool|An instrument is a tool used to create musical sound.",
        "orchestration|instrument distribution|Orchestration plans which instruments are heard and how.",
        "improvisation|instant creation|Improvisation means creating musical ideas in the moment.",
        "jazz|free interpretation tradition|Jazz is known for improvisation and rhythmic flexibility.",
        "classical music|written tradition strength|Classical music often centers on notation, composition and interpretation.",
        "rock|guitar-centered energy|Rock is known for electric guitar, strong rhythm and stage energy.",
        "pop|broad-audience tune|Pop music often aims for memorable structure and wide reach.",
        "rap|rhythmic speech flow|Rap builds expression through words, rhythm and flow.",
        "folk song|community memory|Folk songs carry social memory, emotion and daily life.",
        "maqam|melodic character|Maqam shapes the emotional path and melodic character in Turkish music.",
        "notation|written sound|Notation records pitch and duration in written form.",
        "chord|simultaneous notes|A chord is made of multiple notes heard together.",
        "album|song collection|An album presents songs as a connected body of work.",
        "concert|live performance|A concert creates a live music experience between artist and audience.",
        "producer|recording direction|A producer can shape the sound, arrangement and recording identity of a song.",
        "mastering|final sound polish|Mastering makes a recording sound balanced across playback systems.",
        "sampling|sound reuse|Sampling uses an existing sound piece in a new musical work.",
        "cover|new interpretation|A cover is a new performance of an already known song.",
        "musical composition|original music idea|Composition creates the melodic and structural idea of music.",
        "choir|group voice|A choir is multiple voices singing together in an organized way."
    )
    tarih = Parse-Topics @(
        "chronology|time order|Chronology helps understand events in the order they happened.",
        "civilization|organized social life|Civilization includes cities, writing, law and culture.",
        "empire|multi-people rule|An empire governs large territories and different communities.",
        "republic|popular sovereignty|A republic bases political legitimacy on the people's will.",
        "revolution|radical change|A revolution changes political or social order quickly and deeply.",
        "reform|planned renewal|A reform improves or renews a system without fully destroying it.",
        "Renaissance|rebirth of learning|The Renaissance revived art, science and thought in Europe.",
        "Industrial Revolution|machine production shift|The Industrial Revolution moved production toward machines and factories.",
        "Age of Discovery|global connection|Geographic discoveries expanded trade, colonialism and cultural contact.",
        "migration|movement of people|Migration is movement driven by economic, political or safety reasons.",
        "treaty|formal agreement|A treaty is a written agreement about war, borders or rights.",
        "diplomacy|negotiation path|Diplomacy manages relations between states through talks and representation.",
        "independence|sovereign decision right|Independence means making political decisions without outside control.",
        "constitution|basic legal order|A constitution sets state structure and basic rights.",
        "archaeology|material remains study|Archaeology studies past societies through remains and artifacts.",
        "hieroglyph|picture writing|Hieroglyphs are a picture-based writing system linked especially to Ancient Egypt.",
        "Silk Road|trade network|The Silk Road moved goods and culture between Asia and Europe.",
        "Roman law|legal legacy|Roman law strongly influenced many modern legal systems.",
        "Ottoman Empire|multi-cultural empire|The Ottoman Empire influenced three continents for centuries.",
        "Magna Carta|limited authority idea|Magna Carta is important in the idea that rulers are limited by law.",
        "French Revolution|equality idea|The French Revolution strengthened citizenship, equality and nation ideas.",
        "Turkish War of Independence|national struggle|The Turkish War of Independence is central to sovereignty and independence.",
        "historical source|evidence basis|Historical sources are documents and remains used to interpret the past."
    )
    guncel = Parse-Topics @(
        "misinformation|false information spread|Misinformation spreads wrong or misleading information.",
        "source check|credibility review|Source checking asks who said it and how reliable they are.",
        "date check|time context|Old news can mislead when shared as if it is new.",
        "deepfake|realistic fake media|A deepfake is AI-made audio or video that can look real.",
        "data security|personal protection|Data security tries to prevent unauthorized use of personal information.",
        "subscription economy|small recurring payments|Small monthly fees can become a large total cost.",
        "sustainability|resource balance|Sustainability meets current needs without exhausting future resources.",
        "crisis communication|verified information flow|Clear verified information can reduce panic during a crisis.",
        "disaster readiness|advance planning|Disaster readiness means planning basic needs before a risk happens.",
        "urbanization|city concentration|Urbanization is population and services concentrating in cities.",
        "remote work|location flexibility|Remote work uses digital tools to work outside the office.",
        "AI ethics|responsible use|AI ethics asks about fair, safe and transparent use.",
        "digital footprint|online traces|Digital footprint is the data and behavior trail we leave online.",
        "privacy|control over personal space|Privacy means keeping control over personal information.",
        "public opinion|social perception|Public opinion is the general tendency of society on an issue.",
        "social media trend|fast attention|A trend gains high visibility in a short time.",
        "algorithm bubble|narrow information circle|Algorithms can show similar content and reduce opposing views.",
        "verification|evidence checking|Verification checks the source and proof behind a claim.",
        "energy saving|lower consumption|Energy saving tries to do the same job with less energy.",
        "water saving|resource protection|Water saving means using limited water resources carefully.",
        "food waste|avoidable food loss|Food waste is edible food being thrown away unnecessarily.",
        "carbon footprint|emission impact|Carbon footprint shows the climate impact of activities.",
        "consumer right|buyer protection|Consumer rights protect buyers through information, return and safety rules.",
        "media literacy|news interpretation|Media literacy means reading source, purpose and context.",
        "attention economy|competition for time|The attention economy is platforms competing for user focus."
    )
}

$historyYearFactsTr = @(
    New-YearFact "Kıbrıs Barış Harekâtı" "1974" @("1960", "1983", "1999") "Kıbrıs Barış Harekâtı 20 Temmuz 1974'te başladı."
    New-YearFact "Türkiye Cumhuriyeti'nin ilanı" "1923" @("1919", "1920", "1938") "Türkiye Cumhuriyeti 29 Ekim 1923'te ilan edildi."
    New-YearFact "İstanbul'un fethi" "1453" @("1071", "1299", "1517") "İstanbul 1453 yılında Osmanlı padişahı II. Mehmed tarafından fethedildi."
    New-YearFact "Malazgirt Meydan Muharebesi" "1071" @("1040", "1176", "1299") "Malazgirt Meydan Muharebesi 1071 yılında yapıldı."
    New-YearFact "TBMM'nin açılması" "1920" @("1919", "1921", "1923") "Türkiye Büyük Millet Meclisi 23 Nisan 1920'de açıldı."
    New-YearFact "Atatürk'ün Samsun'a çıkışı" "1919" @("1918", "1920", "1923") "Mustafa Kemal Atatürk 19 Mayıs 1919'da Samsun'a çıktı."
    New-YearFact "Lozan Antlaşması" "1923" @("1920", "1921", "1936") "Lozan Antlaşması 24 Temmuz 1923'te imzalandı."
    New-YearFact "Kadeş Antlaşması" "MÖ 1259" @("MÖ 1274", "MÖ 1200", "1453") "Kadeş Antlaşması Hititler ile Mısırlılar arasında yaklaşık MÖ 1259'da imzalandı."
    New-YearFact "Atatürk'ün doğumu" "1881" @("1876", "1908", "1919") "Mustafa Kemal Atatürk 1881 yılında doğdu."
    New-YearFact "Saltanatın kaldırılması" "1922" @("1920", "1923", "1924") "Saltanat 1 Kasım 1922'de kaldırıldı."
    New-YearFact "Harf Devrimi" "1928" @("1923", "1925", "1934") "Harf Devrimi 1928 yılında yapıldı."
    New-YearFact "Ankara'nın başkent oluşu" "1923" @("1920", "1922", "1938") "Ankara 13 Ekim 1923'te Türkiye'nin başkenti oldu."
    New-YearFact "Çanakkale Deniz Zaferi" "1915" @("1914", "1916", "1918") "Çanakkale Deniz Zaferi 18 Mart 1915'te kazanıldı."
    New-YearFact "Osmanlı Devleti'nin kuruluşu" "1299" @("1071", "1453", "1517") "Osmanlı Devleti'nin kuruluş yılı genel kabulde 1299'dur."
    New-YearFact "Tanzimat Fermanı" "1839" @("1808", "1856", "1876") "Tanzimat Fermanı 1839 yılında ilan edildi."
    New-YearFact "Islahat Fermanı" "1856" @("1839", "1876", "1908") "Islahat Fermanı 1856 yılında ilan edildi."
    New-YearFact "Birinci Meşrutiyet" "1876" @("1839", "1856", "1908") "Birinci Meşrutiyet 1876 yılında ilan edildi."
    New-YearFact "İkinci Meşrutiyet" "1908" @("1876", "1914", "1920") "İkinci Meşrutiyet 1908 yılında ilan edildi."
    New-YearFact "Birinci Dünya Savaşı'nın başlangıcı" "1914" @("1915", "1918", "1939") "Birinci Dünya Savaşı 1914 yılında başladı."
    New-YearFact "Birinci Dünya Savaşı'nın bitişi" "1918" @("1914", "1920", "1939") "Birinci Dünya Savaşı 1918 yılında sona erdi."
    New-YearFact "İkinci Dünya Savaşı'nın başlangıcı" "1939" @("1914", "1918", "1945") "İkinci Dünya Savaşı 1939 yılında başladı."
    New-YearFact "İkinci Dünya Savaşı'nın bitişi" "1945" @("1939", "1949", "1952") "İkinci Dünya Savaşı 1945 yılında sona erdi."
    New-YearFact "Fransız İhtilali" "1789" @("1776", "1815", "1848") "Fransız İhtilali 1789 yılında başladı."
    New-YearFact "Amerikan Bağımsızlık Bildirgesi" "1776" @("1789", "1812", "1861") "Amerikan Bağımsızlık Bildirgesi 1776 yılında yayımlandı."
    New-YearFact "Magna Carta" "1215" @("1071", "1453", "1689") "Magna Carta 1215 yılında kabul edildi."
    New-YearFact "Berlin Duvarı'nın yıkılışı" "1989" @("1945", "1961", "1991") "Berlin Duvarı 1989 yılında yıkıldı."
    New-YearFact "Birleşmiş Milletler'in kuruluşu" "1945" @("1919", "1949", "1955") "Birleşmiş Milletler 1945 yılında kuruldu."
    New-YearFact "NATO'nun kuruluşu" "1949" @("1945", "1952", "1991") "NATO 1949 yılında kuruldu."
    New-YearFact "Montrö Boğazlar Sözleşmesi" "1936" @("1923", "1939", "1945") "Montrö Boğazlar Sözleşmesi 1936 yılında imzalandı."
    New-YearFact "KKTC'nin ilanı" "1983" @("1974", "1980", "1991") "Kuzey Kıbrıs Türk Cumhuriyeti 1983 yılında ilan edildi."
    New-YearFact "Sakarya Meydan Muharebesi" "1921" @("1919", "1920", "1922") "Sakarya Meydan Muharebesi 1921 yılında yapıldı."
    New-YearFact "Büyük Taarruz" "1922" @("1919", "1920", "1921") "Büyük Taarruz 26 Ağustos 1922'de başladı."
    New-YearFact "Mudanya Ateşkes Antlaşması" "1922" @("1919", "1920", "1923") "Mudanya Ateşkes Antlaşması 1922 yılında imzalandı."
    New-YearFact "Amasya Genelgesi" "1919" @("1918", "1920", "1921") "Amasya Genelgesi 1919 yılında yayımlandı."
    New-YearFact "Erzurum Kongresi" "1919" @("1918", "1920", "1923") "Erzurum Kongresi 1919 yılında toplandı."
    New-YearFact "Sivas Kongresi" "1919" @("1918", "1920", "1923") "Sivas Kongresi 1919 yılında toplandı."
    New-YearFact "Cumhuriyetin ilk anayasası" "1924" @("1921", "1923", "1937") "Cumhuriyet döneminin ilk anayasası 1924 Anayasası'dır."
    New-YearFact "Kadınlara milletvekili seçme ve seçilme hakkı" "1934" @("1926", "1930", "1938") "Türkiye'de kadınlara milletvekili seçme ve seçilme hakkı 1934'te verildi."
    New-YearFact "Soyadı Kanunu" "1934" @("1923", "1928", "1938") "Soyadı Kanunu 1934 yılında kabul edildi."
    New-YearFact "Şapka Kanunu" "1925" @("1923", "1928", "1934") "Şapka Kanunu 1925 yılında kabul edildi."
    New-YearFact "Tevhid-i Tedrisat Kanunu" "1924" @("1920", "1923", "1928") "Tevhid-i Tedrisat Kanunu 1924 yılında kabul edildi."
    New-YearFact "Hilafetin kaldırılması" "1924" @("1922", "1923", "1928") "Hilafet 3 Mart 1924'te kaldırıldı."
    New-YearFact "Kurtuluş Savaşı'nın başlangıcı" "1919" @("1918", "1920", "1922") "Kurtuluş Savaşı'nın başlangıcı olarak 19 Mayıs 1919 kabul edilir."
    New-YearFact "Kurtuluş Savaşı'nın sona ermesi" "1922" @("1919", "1920", "1923") "Kurtuluş Savaşı askeri olarak 1922 yılında zaferle sonuçlandı."
    New-YearFact "Osmanlı Devleti'nin sona ermesi" "1922" @("1918", "1920", "1923") "Osmanlı Devleti saltanatın kaldırılmasıyla 1922 yılında sona erdi."
    New-YearFact "Yavuz Sultan Selim'in Mısır Seferi" "1517" @("1453", "1520", "1538") "Yavuz Sultan Selim'in Mısır Seferi 1517 yılında sonuçlandı."
    New-YearFact "Preveze Deniz Zaferi" "1538" @("1453", "1517", "1571") "Preveze Deniz Zaferi 1538 yılında kazanıldı."
    New-YearFact "Mohaç Meydan Muharebesi" "1526" @("1453", "1517", "1538") "Mohaç Meydan Muharebesi 1526 yılında yapıldı."
    New-YearFact "Karlofça Antlaşması" "1699" @("1606", "1718", "1774") "Karlofça Antlaşması 1699 yılında imzalandı."
    New-YearFact "Küçük Kaynarca Antlaşması" "1774" @("1699", "1839", "1856") "Küçük Kaynarca Antlaşması 1774 yılında imzalandı."
    New-YearFact "Sened-i İttifak" "1808" @("1774", "1839", "1876") "Sened-i İttifak 1808 yılında imzalandı."
    New-YearFact "Kavimler Göçü" "375" @("313", "476", "1071") "Kavimler Göçü için genel kabul edilen başlangıç yılı 375'tir."
    New-YearFact "Batı Roma İmparatorluğu'nun yıkılışı" "476" @("375", "1453", "1789") "Batı Roma İmparatorluğu 476 yılında yıkıldı."
    New-YearFact "Doğu Roma'nın İstanbul'da sona ermesi" "1453" @("1071", "1299", "1517") "Doğu Roma İmparatorluğu İstanbul'un 1453'te fethiyle sona erdi."
)

$historyYearFactsEn = @(
    New-YearFact "the Cyprus Peace Operation" "1974" @("1960", "1983", "1999") "The Cyprus Peace Operation began on 20 July 1974."
    New-YearFact "the proclamation of the Republic of Turkey" "1923" @("1919", "1920", "1938") "The Republic of Turkey was proclaimed in 1923."
    New-YearFact "the conquest of Istanbul" "1453" @("1071", "1299", "1517") "Istanbul was conquered in 1453."
    New-YearFact "the Battle of Manzikert" "1071" @("1040", "1176", "1299") "The Battle of Manzikert took place in 1071."
    New-YearFact "the opening of the Turkish Grand National Assembly" "1920" @("1919", "1921", "1923") "The Turkish Grand National Assembly opened in 1920."
    New-YearFact "Atatürk's arrival in Samsun" "1919" @("1918", "1920", "1923") "Atatürk arrived in Samsun on 19 May 1919."
    New-YearFact "the Treaty of Lausanne" "1923" @("1920", "1921", "1936") "The Treaty of Lausanne was signed in 1923."
    New-YearFact "the abolition of the Ottoman sultanate" "1922" @("1920", "1923", "1924") "The Ottoman sultanate was abolished in 1922."
    New-YearFact "the Turkish alphabet reform" "1928" @("1923", "1925", "1934") "The Turkish alphabet reform took place in 1928."
    New-YearFact "Ankara becoming the capital of Turkey" "1923" @("1920", "1922", "1938") "Ankara became Turkey's capital in 1923."
    New-YearFact "the Gallipoli naval victory" "1915" @("1914", "1916", "1918") "The Gallipoli naval victory is marked in 1915."
    New-YearFact "the founding of the Ottoman Empire" "1299" @("1071", "1453", "1517") "The founding year of the Ottoman Empire is commonly accepted as 1299."
    New-YearFact "the Tanzimat Edict" "1839" @("1808", "1856", "1876") "The Tanzimat Edict was proclaimed in 1839."
    New-YearFact "the Reform Edict" "1856" @("1839", "1876", "1908") "The Reform Edict was proclaimed in 1856."
    New-YearFact "the First Constitutional Era of the Ottoman Empire" "1876" @("1839", "1856", "1908") "The First Constitutional Era began in 1876."
    New-YearFact "the Second Constitutional Era of the Ottoman Empire" "1908" @("1876", "1914", "1920") "The Second Constitutional Era began in 1908."
    New-YearFact "the start of World War I" "1914" @("1915", "1918", "1939") "World War I began in 1914."
    New-YearFact "the end of World War I" "1918" @("1914", "1920", "1939") "World War I ended in 1918."
    New-YearFact "the start of World War II" "1939" @("1914", "1918", "1945") "World War II began in 1939."
    New-YearFact "the end of World War II" "1945" @("1939", "1949", "1952") "World War II ended in 1945."
    New-YearFact "the French Revolution" "1789" @("1776", "1815", "1848") "The French Revolution began in 1789."
    New-YearFact "the United States Declaration of Independence" "1776" @("1789", "1812", "1861") "The United States Declaration of Independence was adopted in 1776."
    New-YearFact "Magna Carta" "1215" @("1071", "1453", "1689") "Magna Carta was agreed in 1215."
    New-YearFact "the fall of the Berlin Wall" "1989" @("1945", "1961", "1991") "The Berlin Wall fell in 1989."
    New-YearFact "the founding of the United Nations" "1945" @("1919", "1949", "1955") "The United Nations was founded in 1945."
    New-YearFact "the founding of NATO" "1949" @("1945", "1952", "1991") "NATO was founded in 1949."
    New-YearFact "the Montreux Convention" "1936" @("1923", "1939", "1945") "The Montreux Convention was signed in 1936."
    New-YearFact "the TRNC declaration" "1983" @("1974", "1980", "1991") "The Turkish Republic of Northern Cyprus was declared in 1983."
    New-YearFact "the Battle of Sakarya" "1921" @("1919", "1920", "1922") "The Battle of Sakarya took place in 1921."
    New-YearFact "the Great Offensive" "1922" @("1919", "1920", "1921") "The Great Offensive began in 1922."
    New-YearFact "the Armistice of Mudanya" "1922" @("1919", "1920", "1923") "The Armistice of Mudanya was signed in 1922."
    New-YearFact "the Amasya Circular" "1919" @("1918", "1920", "1921") "The Amasya Circular was issued in 1919."
    New-YearFact "the Erzurum Congress" "1919" @("1918", "1920", "1923") "The Erzurum Congress was held in 1919."
    New-YearFact "the Sivas Congress" "1919" @("1918", "1920", "1923") "The Sivas Congress was held in 1919."
    New-YearFact "Turkey's first republican constitution" "1924" @("1921", "1923", "1937") "Turkey's first republican constitution was adopted in 1924."
    New-YearFact "women's parliamentary voting rights in Turkey" "1934" @("1926", "1930", "1938") "Women gained parliamentary voting and election rights in Turkey in 1934."
    New-YearFact "the Turkish Surname Law" "1934" @("1923", "1928", "1938") "The Turkish Surname Law was adopted in 1934."
    New-YearFact "the Hat Law in Turkey" "1925" @("1923", "1928", "1934") "The Hat Law was adopted in Turkey in 1925."
    New-YearFact "the Law on Unification of Education" "1924" @("1920", "1923", "1928") "The Law on Unification of Education was adopted in 1924."
    New-YearFact "the abolition of the caliphate" "1924" @("1922", "1923", "1928") "The caliphate was abolished in 1924."
    New-YearFact "the start of the Turkish War of Independence" "1919" @("1918", "1920", "1922") "The start of the Turkish War of Independence is commonly linked to 1919."
    New-YearFact "the military end of the Turkish War of Independence" "1922" @("1919", "1920", "1923") "The Turkish War of Independence was militarily won in 1922."
    New-YearFact "the end of the Ottoman Empire" "1922" @("1918", "1920", "1923") "The Ottoman Empire ended with the abolition of the sultanate in 1922."
    New-YearFact "Selim I's Egypt campaign" "1517" @("1453", "1520", "1538") "Selim I's Egypt campaign concluded in 1517."
    New-YearFact "the Battle of Preveza" "1538" @("1453", "1517", "1571") "The Battle of Preveza took place in 1538."
    New-YearFact "the Battle of Mohács" "1526" @("1453", "1517", "1538") "The Battle of Mohács took place in 1526."
    New-YearFact "the Treaty of Karlowitz" "1699" @("1606", "1718", "1774") "The Treaty of Karlowitz was signed in 1699."
    New-YearFact "the Treaty of Küçük Kaynarca" "1774" @("1699", "1839", "1856") "The Treaty of Küçük Kaynarca was signed in 1774."
    New-YearFact "Sened-i İttifak" "1808" @("1774", "1839", "1876") "Sened-i İttifak was signed in 1808."
    New-YearFact "the Migration Period" "375" @("313", "476", "1071") "The Migration Period is commonly dated from 375."
    New-YearFact "the fall of the Western Roman Empire" "476" @("375", "1453", "1789") "The Western Roman Empire fell in 476."
    New-YearFact "the end of the Eastern Roman Empire in Istanbul" "1453" @("1071", "1299", "1517") "The Eastern Roman Empire ended with the conquest of Istanbul in 1453."
)

$simpleFactsTr = @{
    guncel = Parse-SimpleFacts @(
        "Türkiye'nin başkenti neresidir|Ankara|İstanbul,İzmir,Bursa|Türkiye'nin başkenti Ankara'dır."
        "Bir hafta kaç gündür|7|5,6,8|Bir hafta 7 gündür."
        "Bir yıl genelde kaç aydır|12|10,11,13|Bir takvim yılı 12 aydır."
        "Bir gün kaç saattir|24|12,18,30|Bir gün 24 saattir."
        "Trafik ışığında kırmızı ne anlama gelir|Dur|Geç,Hızlan,Dön|Kırmızı ışık dur anlamına gelir."
        "Türkiye'nin para birimi nedir|Türk lirası|Dolar,Euro,Sterlin|Türkiye'nin resmi para birimi Türk lirasıdır."
        "Acil yardım için Türkiye'de hangi numara aranır|112|110,155,184|Türkiye'de acil çağrı numarası 112'dir."
        "Bir düzine kaç adettir|12|10,11,13|Bir düzine 12 adettir."
        "Dünya'nın doğal uydusu nedir|Ay|Mars,Güneş,Venüs|Dünya'nın doğal uydusu Ay'dır."
        "Suyun donma noktası kaç derecedir|0 derece|10 derece,50 derece,100 derece|Su deniz seviyesinde 0 derecede donar."
        "Bir haberde ilk ne kontrol edilir|Kaynak|Renk,Logo,Yorum|Haber değerlendirirken kaynak kontrolü önemlidir."
        "Kimlik kartında hangi bilgi bulunur|Ad soyad|Ayakkabı numarası,Şarkı listesi,Oyun skoru|Kimlik kartı temel kişisel bilgileri taşır."
        "Güneş hangi yönden doğar|Doğu|Batı,Kuzey,Güney|Güneş doğudan doğar."
        "Türkiye hangi yarım kürededir|Kuzey|Güney,Batı,Doğu|Türkiye Kuzey Yarımküre'dedir."
        "Market alışverişinde ödeme için ne kullanılır|Para|Pusula,Harita,Düdük|Alışverişte ödeme para veya kartla yapılır."
        "Okulda ders anlatan kişiye ne denir|Öğretmen|Doktor,Şoför,Aşçı|Öğretmen ders anlatır ve öğrenciyi yönlendirir."
        "Hastanede hastalara bakan meslek hangisidir|Doktor|Pilot,Terzi,Kasiyer|Doktor hastalıkların teşhis ve tedavisiyle ilgilenir."
        "Kütüphanede genelde ne bulunur|Kitap|Tencere,Lastik,Çekiç|Kütüphane kitap ve bilgi kaynaklarının bulunduğu yerdir."
        "Elektrik kesilince çalışan aydınlatma aracı nedir|El feneri|Çamaşır makinesi,Buzdolabı,Fırın|El feneri taşınabilir ışık sağlar."
        "Yağmurdan korunmak için ne kullanılır|Şemsiye|Gözlük,Terlik,Tarak|Şemsiye yağmurdan korunmak için kullanılır."
    )
    teknoloji = Parse-SimpleFacts @(
        "Bilgisayarda yazı yazmak için ne kullanılır|Klavye|Hoparlör,Yazıcı,Kamera|Klavye bilgisayara yazı girmek için kullanılır."
        "Ekrandaki oku hareket ettiren araç nedir|Mouse|Mikrofon,Şarj cihazı,Hoparlör|Mouse imleci hareket ettirir."
        "Telefonu doldurmak için ne kullanılır|Şarj cihazı|Klavye,Projeksiyon,Modem|Telefon şarj cihazıyla doldurulur."
        "Wi-Fi ne sağlar|Kablosuz internet|Kağıt baskı,Su ısıtma,Ses kaydı|Wi-Fi kablosuz ağ bağlantısı sağlar."
        "QR kod genelde neyle okutulur|Kamera|Klavye,Hoparlör,Fare|QR kod kamera ile okutulur."
        "E-posta göndermek için genelde ne gerekir|İnternet|Makas,Radyo,Pil kapağı|E-posta internet üzerinden gönderilir."
        "Şifre ne işe yarar|Hesabı korur|Ekranı siler,Sesi artırır,Fotoğraf çeker|Şifre hesap güvenliği için kullanılır."
        "Bilgisayarda silinen dosyalar çoğu zaman nereye gider|Geri dönüşüm kutusu|Takvim,Kamera,Saat|Silinen dosyalar genelde geri dönüşüm kutusuna gider."
        "İnternet sitesini açan programa ne denir|Tarayıcı|Defter,Hoparlör,Pusula|Tarayıcı web sitelerini açar."
        "USB bellek ne saklar|Dosya|Su,Yiyecek,Giysi|USB bellek dosya saklamak için kullanılır."
        "Aşağıdakilerden hangisi depolama aygıtı değildir|Hoparlör|USB bellek,Sabit disk,Hafıza kartı|Hoparlör ses çıkışı verir; veri depolama aygıtı değildir."
        "Kulaklık ne için kullanılır|Ses dinlemek|Yemek pişirmek,Fotoğraf basmak,Ekran silmek|Kulaklık ses dinlemek için kullanılır."
        "Hoparlör ne verir|Ses|Koku,Işık,Isı|Hoparlör ses çıkışı sağlar."
        "Kamera ne çeker|Fotoğraf|Para,Su,Yazı tahtası|Kamera fotoğraf veya video çeker."
        "Mikrofon neyi alır|Ses|Renk,Koku,Tat|Mikrofon sesi algılar."
        "Modem neye bağlanmayı sağlar|İnternete|Buzdolabına,Pusulaya,Kaleme|Modem internet bağlantısında kullanılır."
        "Uygulama indirmek için telefonlarda hangi mağaza kullanılır|Google Play|Not Defteri,Hesap Makinesi,Takvim|Android'de uygulamalar Google Play'den indirilebilir."
        "Bluetooth genelde ne için kullanılır|Yakın cihazları bağlamak|Uzay yolculuğu yapmak,Su ölçmek,Kağıt kesmek|Bluetooth yakındaki cihazları bağlar."
        "Dokunmatik ekranda işlem yapmak için ne kullanılır|Parmak|Çekiç,Makas,Fırça|Dokunmatik ekran parmakla kullanılabilir."
        "Pil yüzdesi nedir|Şarj durumu|İnternet hızı,Ses kalitesi,Ekran boyu|Pil yüzdesi cihazda kalan enerjiyi gösterir."
        "Güncelleme genelde neyi düzeltir|Hata ve güvenliği|Ayakkabı rengini,Ev adresini,Saat dilimini|Güncellemeler hata ve güvenlik düzeltmeleri getirebilir."
    )
    sanat = Parse-SimpleFacts @(
        "Resim yapan kişiye ne denir|Ressam|Doktor,Pilot,Hakem|Ressam resim yapan sanatçıdır."
        "Şiir yazan kişiye ne denir|Şair|Kaleci,Aşçı,Mühendis|Şair şiir yazan kişidir."
        "Kitap yazan kişiye ne denir|Yazar|Terzi,Kasiyer,Şoför|Yazar kitap veya metin yazar."
        "Mona Lisa'nın ressamı kimdir|Leonardo da Vinci|Picasso,Van Gogh,Michelangelo|Mona Lisa Leonardo da Vinci tarafından yapılmıştır."
        "Sarı ile mavi karışınca hangi renk oluşur|Yeşil|Kırmızı,Siyah,Mor|Sarı ve mavi karışınca yeşil oluşur."
        "Kırmızı ile beyaz karışınca hangi renk oluşur|Pembe|Yeşil,Mavi,Siyah|Kırmızı ve beyaz karışınca pembe elde edilir."
        "Heykel yapan sanatçıya ne denir|Heykeltıraş|Şair,Oyuncu,Spiker|Heykeltıraş heykel yapan sanatçıdır."
        "Tiyatro oyunu nerede oynanır|Sahnede|Havuzda,Otobüste,Markette|Tiyatro oyunu sahnede oynanır."
        "Fotoğraf çekmek için hangi araç kullanılır|Kamera|Fırın,Tencere,Pusula|Kamera fotoğraf çekmek için kullanılır."
        "Sinema salonunda ne izlenir|Film|Maç bileti,Yemek tarifi,Harita|Sinema salonunda film izlenir."
        "Müzede genelde ne sergilenir|Eser|Araba lastiği,Market fişi,Su şişesi|Müzelerde sanat veya tarih eserleri sergilenir."
        "Bir resimde kullanılan temel malzemelerden biri nedir|Boya|Çimento,Motor yağı,Tornavida|Boya resim yapımında kullanılan temel malzemelerden biridir."
        "Oyuncuların sahnede canlandırdığı sanat dalı nedir|Tiyatro|Muhasebe,Marangozluk,Koşu|Tiyatro sahnede canlandırmaya dayalı sanattır."
        "Roman hangi tür eserdir|Edebi eser|Spor aracı,Mutfak ürünü,Trafik levhası|Roman edebiyat türlerinden biridir."
        "Karagöz ve Hacivat hangi sanata örnektir|Gölge oyunu|Yağlı boya,Bale,Opera|Karagöz ve Hacivat geleneksel gölge oyunudur."
        "Çizgi filmde görüntü genelde nasıl oluşur|Çizimlerle|Yalnızca sayılarla,Taşlarla,Kokularla|Çizgi film çizim veya animasyonlarla oluşur."
        "Bir tablonun etrafındaki parçaya ne denir|Çerçeve|Klavye,Kapak,Pervane|Çerçeve tabloyu çevreleyen parçadır."
        "Sahnede rol yapan kişiye ne denir|Oyuncu|Hakem,Kasap,Dişçi|Oyuncu sahnede veya filmde rol yapar."
        "Bir şarkının sözlerini yazan kişiye ne denir|Söz yazarı|Kaleci,Manav,Pilot|Söz yazarı şarkı sözlerini yazar."
        "Dans hangi sanatla ilgilidir|Hareket|Matkap,Süpürge,Pusula|Dans bedensel hareketle yapılan sahne sanatıdır."
    )
    spor = Parse-SimpleFacts @(
        "Futbolda bir takım sahaya kaç oyuncuyla çıkar|11|5,6,9|Futbolda bir takım sahaya 11 oyuncuyla çıkar."
        "Futbol kaç kişiyle oynanır|11'e 11|5'e 5,6'ya 6,7'ye 7|Futbol sahada iki takımın 11'er oyuncusuyla oynanır."
        "Basketbolda sahadaki bir takım kaç oyuncudur|5|6,7,11|Basketbolda sahada bir takım 5 oyuncudan oluşur."
        "Voleybolda sahadaki bir takım kaç oyuncudur|6|5,7,11|Voleybolda sahada bir takım 6 oyuncuyla oynar."
        "Futbolda top kaleye girerse ne olur|Gol|Faul,Korner,Set|Futbolda top kaleye girerse gol olur."
        "Kaleyi koruyan oyuncuya ne denir|Kaleci|Forvet,Hakem,Antrenör|Kaleci kaleyi koruyan oyuncudur."
        "Teniste topa neyle vurulur|Raket|Sopa,Eldiven,Kürek|Teniste topa raketle vurulur."
        "Basketbolda top nereye atılır|Potaya|Kaleye,Fileye,Çukura|Basketbolda sayı için top potaya atılır."
        "Yüzme sporu genelde nerede yapılır|Havuzda|Sahada,Pistte,Ringde|Yüzme havuzda veya açık suda yapılır."
        "Boks sporunda elde ne olur|Eldiven|Raket,Kask,Kalem|Boksta sporcular eldiven kullanır."
        "Olimpiyat bayrağında kaç halka vardır|5|3,4,6|Olimpiyat bayrağında 5 halka vardır."
        "Futbolda sarı kart ne anlama gelir|Uyarı|Gol,Şampiyonluk,Mola|Sarı kart oyuncuya uyarı anlamına gelir."
        "Maçı yöneten kişiye ne denir|Hakem|Seyirci,Kaleci,Masör|Hakem maçı yönetir."
        "Satrançta en önemli taş hangisidir|Şah|Piyon,At,Kale|Satrançta şah oyunun merkezindeki en önemli taştır."
        "Koşu pisti hangi sporla ilgilidir|Atletizm|Satranç,Yüzme,Boks|Koşu pistleri atletizmde kullanılır."
        "Futbol topunun şekli nasıldır|Yuvarlak|Kare,Üçgen,Düz|Futbol topu yuvarlaktır."
        "Bisiklet sürerken güvenlik için başa ne takılır|Kask|Eldiven,Kravat,Atkı|Bisiklette kask güvenlik için önemlidir."
        "Halterde sporcu ne kaldırır|Ağırlık|Top,Raket,File|Halter ağırlık kaldırmaya dayalı bir spordur."
        "Futbolda maç kaç devreden oluşur|2|1,3,4|Futbol maçı iki devreden oluşur."
        "Masa tenisinde topa neyle vurulur|Raket|Ayak,Eldiven,Kürek|Masa tenisinde raket kullanılır."
        "Kayak sporu genelde hangi zeminde yapılır|Kar|Kum,Çim,Asfalt|Kayak çoğunlukla kar üzerinde yapılır."
        "Mete Gazoz hangi spor dalında olimpiyat şampiyonu oldu|Okçuluk|Güreş,Boks,Yüzme|Mete Gazoz okçulukta olimpiyat şampiyonu olmuştur."
        "Mete Gazoz ne zaman olimpiyat şampiyonu oldu|31 Temmuz 2021|6 Ağustos 2023,29 Ekim 1923,19 Mayıs 1919|Mete Gazoz 31 Temmuz 2021'de olimpiyat şampiyonu oldu."
        "Mete Gazoz ne zaman dünya şampiyonu oldu|6 Ağustos 2023|31 Temmuz 2021,23 Nisan 1920,10 Kasım 1938|Mete Gazoz 6 Ağustos 2023'te dünya şampiyonu oldu."
        "Mete Gazoz 2023'te hangi şehirde dünya şampiyonu oldu|Berlin|Tokyo,Paris,Roma|Mete Gazoz 2023 Dünya Okçuluk Şampiyonası'nda Berlin'de dünya şampiyonu oldu."
        "Mete Gazoz 2023 Dünya Şampiyonası finalinde kimi yendi|Eric Peters|Mauro Nespoli,Brady Ellison,Takaharu Furukawa|Mete Gazoz 2023 dünya şampiyonluğu finalinde Eric Peters'ı yendi."
        "Mete Gazoz olimpiyat finalinde kimi yendi|Mauro Nespoli|Eric Peters,Brady Ellison,Marcus D'almeida|Mete Gazoz Tokyo 2020 finalinde Mauro Nespoli'yi yendi."
    )
    muzik = Parse-SimpleFacts @(
        "Do re mi dizisinin ilk notası nedir|Do|Re,Mi,Fa|Do re mi dizisi Do ile başlar."
        "Gitar hangi tür çalgıdır|Telli|Vurmalı,Üflemeli,Tuşlu|Gitar telli bir çalgıdır."
        "Piyano hangi tür çalgıdır|Tuşlu|Telli,Üflemeli,Vurmalı|Piyano tuşlu bir çalgıdır."
        "Davul hangi tür çalgıdır|Vurmalı|Telli,Tuşlu,Üflemeli|Davul vurmalı bir çalgıdır."
        "Şarkı söyleyen kişiye ne denir|Şarkıcı|Hakem,Doktor,Pilot|Şarkıcı şarkı söyleyen kişidir."
        "Sahnede mikrofon neyi yükseltmek için kullanılır|Ses|Renk,Koku,Tat|Mikrofon sesi almak veya yükseltmek için kullanılır."
        "Müzik dinlerken kulaklık ne için kullanılır|Müzik dinlemek|Resim çizmek,Yemek pişirmek,Top sürmek|Kulaklık müzik dinlemek için kullanılır."
        "Konser genelde nerede yapılır|Sahnede|Mutfakta,Havuzda,Otobüste|Konser sahnede veya konser alanında yapılır."
        "Ritim neyle ilgilidir|Vuruş düzeni|Renk karışımı,Kitap sayısı,Yol uzunluğu|Ritim vuruşların düzenidir."
        "Tempo müzikte ne anlama gelir|Hız|Renk,Koku,Ağırlık|Tempo müziğin hızını anlatır."
        "Orkestrayı yöneten kişiye ne denir|Şef|Kaleci,Spiker,Kasiyer|Orkestra şef tarafından yönetilir."
        "Keman genelde neyle çalınır|Yay|Kalem,Çekiç,Kaşık|Keman yayla çalınan telli bir çalgıdır."
        "Flüt hangi tür çalgıdır|Üflemeli|Telli,Vurmalı,Tuşlu|Flüt üflemeli bir çalgıdır."
        "Nakarat şarkıda genelde ne olur|Tekrarlanan bölüm|Sessizlik,Sahne ışığı,Bilet|Nakarat şarkıda tekrarlanan bölümdür."
        "Şarkıların toplandığı çalışmaya ne denir|Albüm|Hakem,Forma,Saha|Albüm birçok şarkıyı içerebilir."
        "Konserde hoparlör ne verir|Ses|Koku,Su,Işık|Hoparlör ses çıkışı sağlar."
        "Bağlama hangi tür çalgıdır|Telli|Tuşlu,Vurmalı,Üflemeli|Bağlama telli bir Türk halk çalgısıdır."
        "Nota neyi yazmak için kullanılır|Müzik|Yemek,Spor skoru,Harita|Nota müziği yazmak için kullanılır."
        "Rap müzikte sözler genelde nasıl söylenir|Ritimli|Sessiz,Yavaşça çizilerek,Resimle|Rap müzikte sözler ritmik biçimde söylenir."
        "Marşlar genelde nasıl bir duygu verir|Coşku|Uyku,Açlık,Susuzluk|Marşlar çoğu zaman coşkulu bir duygu taşır."
    )
    tarih = Parse-SimpleFacts @(
        "İstanbul'un fethi hangi yıldadır|1453|1071,1923,1919|İstanbul 1453 yılında fethedilmiştir."
        "Türkiye Cumhuriyeti hangi yılda ilan edildi|1923|1919,1920,1938|Türkiye Cumhuriyeti 1923 yılında ilan edildi."
        "Cumhuriyet ne zaman ilan edilmiştir|29 Ekim 1923|23 Nisan 1920,19 Mayıs 1919,10 Kasım 1938|Türkiye Cumhuriyeti 29 Ekim 1923'te ilan edildi."
        "Atatürk Samsun'a hangi yılda çıktı|1919|1920,1923,1938|Atatürk 19 Mayıs 1919'da Samsun'a çıktı."
        "TBMM hangi yılda açıldı|1920|1919,1923,1938|Türkiye Büyük Millet Meclisi 1920'de açıldı."
        "Malazgirt Zaferi hangi yıldadır|1071|1453,1299,1923|Malazgirt Zaferi 1071 yılındadır."
        "Kıbrıs Barış Harekâtı hangi yılda yapıldı|1974|1960,1983,1999|Kıbrıs Barış Harekâtı 1974'te yapılmıştır."
        "Fransız İhtilali hangi yıldadır|1789|1453,1914,1923|Fransız İhtilali 1789 yılında gerçekleşti."
        "Lozan Antlaşması hangi yılda imzalandı|1923|1919,1920,1936|Lozan Antlaşması 1923'te imzalandı."
        "Kadeş Antlaşması kimler arasında imzalandı|Hititler ve Mısırlılar|Osmanlı ve Bizans,Roma ve Persler,İngiltere ve Fransa|Kadeş Antlaşması Hititler ile Mısırlılar arasında imzalandı."
        "Lozan Barış Antlaşması hangi devletlerle imzalanmıştır|İtilaf Devletleri|İttifak Devletleri,Balkan Devletleri,Orta Asya devletleri|Lozan Barış Antlaşması Türkiye ile İtilaf Devletleri arasında imzalandı."
        "İpek Yolu'nun kuruluş amacı nedir|Ticaret yapmak|Savaş başlatmak,Taht değiştirmek,Yeni alfabe oluşturmak|İpek Yolu, Asya ile Avrupa arasında ticareti ve kültürel etkileşimi kolaylaştıran bir yol ağıdır."
        "İpek Yolu genelde hangi faaliyetle ilişkilidir|Ticaret|Seçim,Uzay yolculuğu,Futbol turnuvası|İpek Yolu tarih boyunca ticaret yolları bütünü olarak bilinir."
        "İpek Yolu hangi bölgeler arasında uzanmıştır|Asya ve Avrupa|Afrika ve Antarktika,Güney Amerika ve Avustralya,Kuzey Kutbu ve Ekvator|İpek Yolu Asya ile Avrupa arasında uzanan ticaret ağlarını anlatır."
        "Osmanlı Devleti'nin kurucusu kimdir|Osman Bey|Fatih Sultan Mehmet,Yavuz Sultan Selim,Kanuni Sultan Süleyman|Osmanlı Devleti'nin kurucusu Osman Bey kabul edilir."
        "İstanbul'u fetheden padişah kimdir|Fatih Sultan Mehmet|Osman Bey,Yavuz Sultan Selim,Kanuni Sultan Süleyman|İstanbul'u Fatih Sultan Mehmet fethetmiştir."
        "Anıtkabir hangi şehirdedir|Ankara|İstanbul,İzmir,Bursa|Anıtkabir Ankara'dadır."
        "Çanakkale Zaferi hangi yıldadır|1915|1919,1920,1923|Çanakkale Zaferi 1915 yılıyla anılır."
        "İkinci Dünya Savaşı hangi yılda başladı|1939|1914,1923,1945|İkinci Dünya Savaşı 1939'da başladı."
        "Harf Devrimi hangi yıldadır|1928|1923,1934,1938|Harf Devrimi 1928 yılında yapılmıştır."
        "Kurtuluş Savaşı'nın önderi kimdir|Mustafa Kemal Atatürk|Osman Bey,Fatih Sultan Mehmet,Mimar Sinan|Kurtuluş Savaşı'nın önderi Mustafa Kemal Atatürk'tür."
        "Cumhuriyetin ilk cumhurbaşkanı kimdir|Mustafa Kemal Atatürk|İsmet İnönü,Celal Bayar,Fevzi Çakmak|Türkiye Cumhuriyeti'nin ilk cumhurbaşkanı Atatürk'tür."
        "Amerika kıtasının keşfi hangi yılla anılır|1492|1453,1789,1919|Amerika'nın keşfi 1492 yılıyla anılır."
        "Tanzimat Fermanı hangi yıldadır|1839|1808,1856,1876|Tanzimat Fermanı 1839'da ilan edildi."
        "Osmanlı'da ilk anayasa hangi adla bilinir|Kanun-i Esasi|Lozan,Sevr,Tanzimat|Osmanlı'nın ilk anayasası Kanun-i Esasi'dir."
        "Saltanat hangi yılda kaldırıldı|1922|1920,1923,1924|Saltanat 1922 yılında kaldırıldı."
    )
}

$simpleFactsEn = @{
    guncel = Parse-SimpleFacts @(
        "what is the capital of Turkey|Ankara|Istanbul,Izmir,Bursa|The capital of Turkey is Ankara."
        "how many days are in a week|7|5,6,8|A week has 7 days."
        "how many months are in a year|12|10,11,13|A calendar year has 12 months."
        "how many hours are in a day|24|12,18,30|A day has 24 hours."
        "what does a red traffic light mean|Stop|Go,Speed up,Turn|A red traffic light means stop."
        "what is Turkey's currency|Turkish lira|Dollar,Euro,Pound|Turkey's official currency is the Turkish lira."
        "which emergency number is used in Turkey|112|110,155,184|Turkey uses 112 as the emergency number."
        "how many items are in a dozen|12|10,11,13|A dozen means 12 items."
        "what is Earth's natural satellite|Moon|Mars,Sun,Venus|Earth's natural satellite is the Moon."
        "at what temperature does water freeze|0 degrees|10 degrees,50 degrees,100 degrees|Water freezes at 0 degrees Celsius at sea level."
        "what should be checked first in news|Source|Color,Logo,Comment|Checking the source is important in news."
        "where does the Sun rise|East|West,North,South|The Sun rises in the east."
        "what is used to pay in shopping|Money|Compass,Map,Whistle|Shopping is paid for with money or card."
        "who teaches lessons at school|Teacher|Doctor,Driver,Cook|A teacher teaches lessons."
        "who treats patients in hospital|Doctor|Pilot,Tailor,Cashier|Doctors diagnose and treat patients."
        "what is mostly found in a library|Books|Pans,Tires,Hammers|Libraries contain books and information sources."
        "what protects from rain|Umbrella|Glasses,Slippers,Comb|An umbrella protects from rain."
        "what is used for portable light|Flashlight|Oven,Fridge,Washer|A flashlight gives portable light."
        "what information is on an ID card|Name|Shoe size,Song list,Game score|An ID card carries basic identity information."
        "which hemisphere is Turkey in|Northern|Southern,Western,Eastern|Turkey is in the Northern Hemisphere."
    )
    teknoloji = Parse-SimpleFacts @(
        "what is used to type on a computer|Keyboard|Speaker,Printer,Camera|A keyboard is used for typing."
        "what moves the pointer on screen|Mouse|Microphone,Charger,Speaker|A mouse moves the pointer."
        "what charges a phone|Charger|Keyboard,Projector,Modem|A charger charges a phone."
        "what does Wi-Fi provide|Wireless internet|Paper printing,Water heating,Voice recording|Wi-Fi provides wireless network access."
        "what usually scans a QR code|Camera|Keyboard,Speaker,Mouse|A camera can scan QR codes."
        "what is usually needed to send email|Internet|Scissors,Radio,Battery cover|Email is sent through the internet."
        "what does a password do|Protects account|Cleans screen,Raises sound,Takes photos|A password helps protect an account."
        "what opens websites|Browser|Notebook,Speaker,Compass|A browser opens websites."
        "what does a USB drive store|Files|Water,Food,Clothes|A USB drive stores files."
        "what are headphones used for|Listening sound|Cooking food,Printing photos,Cleaning screen|Headphones are used to listen to sound."
        "what does a speaker produce|Sound|Smell,Light,Heat|A speaker produces sound."
        "what does a camera take|Photo|Money,Water,Board|A camera takes photos or videos."
        "what does a microphone capture|Sound|Color,Smell,Taste|A microphone captures sound."
        "what connects a home to internet|Modem|Fridge,Compass,Pen|A modem helps connect to the internet."
        "which store is common on Android|Google Play|Notepad,Calculator,Calendar|Android apps can be downloaded from Google Play."
        "what is Bluetooth mainly for|Nearby connection|Space travel,Water measure,Paper cutting|Bluetooth connects nearby devices."
        "what is used on a touchscreen|Finger|Hammer,Scissors,Brush|A touchscreen can be used with a finger."
        "what does battery percentage show|Charge level|Internet speed,Sound quality,Screen size|Battery percentage shows remaining charge."
        "what can an update fix|Bugs and security|Shoe color,Home address,Time zone|Updates can fix bugs and security issues."
        "where do deleted files often go|Recycle bin|Calendar,Camera,Clock|Deleted computer files often go to the recycle bin."
    )
    sanat = Parse-SimpleFacts @(
        "what do we call a person who paints|Painter|Doctor,Pilot,Referee|A painter creates paintings."
        "what do we call a person who writes poems|Poet|Goalkeeper,Cook,Engineer|A poet writes poems."
        "what do we call a person who writes books|Writer|Tailor,Cashier,Driver|A writer writes books or texts."
        "who painted the Mona Lisa|Leonardo da Vinci|Picasso,Van Gogh,Michelangelo|The Mona Lisa was painted by Leonardo da Vinci."
        "what color comes from yellow and blue|Green|Red,Black,Purple|Yellow and blue make green."
        "what color comes from red and white|Pink|Green,Blue,Black|Red and white make pink."
        "what do we call a person who makes sculpture|Sculptor|Poet,Actor,Announcer|A sculptor makes sculptures."
        "where is theatre performed|Stage|Pool,Bus,Market|Theatre is performed on stage."
        "what takes a photograph|Camera|Oven,Pan,Compass|A camera takes photographs."
        "what is watched in a cinema|Film|Match ticket,Recipe,Map|Films are watched in cinemas."
        "what is usually displayed in a museum|Artwork|Car tire,Receipt,Water bottle|Museums display art or historical works."
        "what is a basic painting material|Paint|Cement,Motor oil,Screwdriver|Paint is a basic art material."
        "what art uses actors on stage|Theatre|Accounting,Carpentry,Running|Theatre uses actors on stage."
        "what type of work is a novel|Literary work|Sports tool,Kitchen item,Traffic sign|A novel is a literary work."
        "Karagoz and Hacivat are an example of what|Shadow play|Oil painting,Ballet,Opera|Karagoz and Hacivat are traditional shadow play."
        "what surrounds a painting|Frame|Keyboard,Cover,Propeller|A frame surrounds a painting."
        "what do we call a person acting on stage|Actor|Referee,Butcher,Dentist|An actor performs roles."
        "who writes song lyrics|Lyricist|Goalkeeper,Greengrocer,Pilot|A lyricist writes song words."
        "dance is mostly about what|Movement|Drill,Broom,Compass|Dance is an art of movement."
        "cartoons are usually made with what|Drawings|Only numbers,Stones,Smells|Cartoons use drawings or animation."
    )
    spor = Parse-SimpleFacts @(
        "how many players does a football team have on field|11|5,6,9|A football team has 11 players on the field."
        "how many players does a basketball team have on court|5|6,7,11|A basketball team has 5 players on court."
        "how many players does a volleyball team have on court|6|5,7,11|A volleyball team has 6 players on court."
        "what is it called when the football enters the goal|Goal|Foul,Corner,Set|A ball entering the goal is a goal."
        "who protects the goal|Goalkeeper|Forward,Referee,Coach|A goalkeeper protects the goal."
        "what is used to hit the ball in tennis|Racket|Stick,Glove,Oar|Tennis uses a racket."
        "where is the ball thrown in basketball|Hoop|Goal,Net,Hole|Basketball shots go to the hoop."
        "where is swimming usually done|Pool|Field,Track,Ring|Swimming is done in a pool or open water."
        "what is worn on hands in boxing|Gloves|Racket,Helmet,Pen|Boxers wear gloves."
        "how many rings are on the Olympic flag|5|3,4,6|The Olympic flag has 5 rings."
        "what does a yellow card mean in football|Warning|Goal,Championship,Break|A yellow card is a warning."
        "who manages a match|Referee|Spectator,Goalkeeper,Physio|A referee manages a match."
        "what is the most important chess piece|King|Pawn,Knight,Rook|The king is the key chess piece."
        "which sport uses a running track|Athletics|Chess,Swimming,Boxing|Running tracks are used in athletics."
        "what shape is a football|Round|Square,Triangle,Flat|A football is round."
        "what is worn on the head for cycling safety|Helmet|Gloves,Tie,Scarf|A helmet helps protect cyclists."
        "what does a weightlifter lift|Weight|Ball,Racket,Net|Weightlifting is based on lifting weights."
        "how many halves are in a football match|2|1,3,4|A football match has two halves."
        "what is used in table tennis|Racket|Foot,Glove,Oar|Table tennis uses a racket."
        "what surface is skiing mostly done on|Snow|Sand,Grass,Asphalt|Skiing is mostly done on snow."
    )
    muzik = Parse-SimpleFacts @(
        "what is the first note in do re mi|Do|Re,Mi,Fa|The do re mi scale starts with Do."
        "what type of instrument is a guitar|String|Percussion,Wind,Keyboard|A guitar is a string instrument."
        "what type of instrument is a piano|Keyboard|String,Wind,Percussion|A piano is a keyboard instrument."
        "what type of instrument is a drum|Percussion|String,Keyboard,Wind|A drum is a percussion instrument."
        "what do we call a person who sings|Singer|Referee,Doctor,Pilot|A singer sings songs."
        "what does a stage microphone capture|Sound|Color,Smell,Taste|A microphone captures sound."
        "what are headphones used for when listening to music|Listening music|Drawing,Cooking,Dribbling|Headphones are used to listen to music."
        "where is a concert usually performed|Stage|Kitchen,Pool,Bus|A concert is performed on stage or in a venue."
        "what is rhythm about|Beat pattern|Color mix,Page count,Road length|Rhythm is the pattern of beats."
        "what does tempo mean in music|Speed|Color,Smell,Weight|Tempo means the speed of music."
        "who leads an orchestra|Conductor|Goalkeeper,Announcer,Cashier|A conductor leads an orchestra."
        "what is a violin usually played with|Bow|Pen,Hammer,Spoon|A violin is usually played with a bow."
        "what type of instrument is a flute|Wind|String,Percussion,Keyboard|A flute is a wind instrument."
        "what is a chorus in a song|Repeated part|Silence,Stage light,Ticket|A chorus is a repeated part."
        "what is a collection of songs called|Album|Referee,Uniform,Field|An album can contain many songs."
        "what does a concert speaker produce|Sound|Smell,Water,Light|A speaker produces sound."
        "what type of instrument is bağlama|String|Keyboard,Percussion,Wind|Bağlama is a Turkish string instrument."
        "what is notation used to write|Music|Food,Sports score,Map|Notation writes music."
        "how are rap lyrics often delivered|Rhythmically|Silently,By drawing,With pictures|Rap lyrics are often delivered rhythmically."
        "what feeling do marches often give|Excitement|Sleep,Hunger,Thirst|Marches often create excitement."
    )
    tarih = Parse-SimpleFacts @(
        "in which year was Istanbul conquered|1453|1071,1923,1919|Istanbul was conquered in 1453."
        "in which year was the Republic of Turkey declared|1923|1919,1920,1938|The Republic of Turkey was declared in 1923."
        "in which year did Atatürk land in Samsun|1919|1920,1923,1938|Atatürk landed in Samsun in 1919."
        "in which year did the Turkish parliament open|1920|1919,1923,1938|The Turkish parliament opened in 1920."
        "in which year was the Battle of Manzikert|1071|1453,1299,1923|The Battle of Manzikert was in 1071."
        "in which year was the Cyprus Peace Operation|1974|1960,1983,1999|The Cyprus Peace Operation was in 1974."
        "in which year was the French Revolution|1789|1453,1914,1923|The French Revolution was in 1789."
        "in which year was the Treaty of Lausanne signed|1923|1919,1920,1936|The Treaty of Lausanne was signed in 1923."
        "who founded the Ottoman Empire|Osman Bey|Mehmed II,Selim I,Suleiman|Osman Bey is accepted as the founder of the Ottoman Empire."
        "who conquered Istanbul|Mehmed II|Osman Bey,Selim I,Suleiman|Istanbul was conquered by Mehmed II."
        "which city is Anıtkabir in|Ankara|Istanbul,Izmir,Bursa|Anıtkabir is in Ankara."
        "in which year was the Gallipoli victory|1915|1919,1920,1923|The Gallipoli victory is associated with 1915."
        "in which year did World War II begin|1939|1914,1923,1945|World War II began in 1939."
        "in which year was the Turkish alphabet reform|1928|1923,1934,1938|The Turkish alphabet reform was in 1928."
        "who led the Turkish War of Independence|Mustafa Kemal Atatürk|Osman Bey,Mehmed II,Mimar Sinan|Atatürk led the Turkish War of Independence."
        "who was Turkey's first president|Mustafa Kemal Atatürk|İsmet İnönü,Celal Bayar,Fevzi Çakmak|Atatürk was Turkey's first president."
        "which year is linked with the discovery of America|1492|1453,1789,1919|The discovery of America is linked with 1492."
        "in which year was the Tanzimat Edict|1839|1808,1856,1876|The Tanzimat Edict was declared in 1839."
        "what was the first Ottoman constitution called|Kanun-i Esasi|Lausanne,Sevres,Tanzimat|The first Ottoman constitution was Kanun-i Esasi."
        "in which year was the sultanate abolished|1922|1920,1923,1924|The sultanate was abolished in 1922."
    )
}

$extraTopicsTr = @{
    ekonomi = @(
        "gelir|kazanılan parayı", "gider|harcanan parayı", "tasarruf|gelirin ayrılan bölümünü",
        "yatırım|gelecek getiri için kaynak ayırmayı", "vergi|kamuya yapılan zorunlu ödemeyi",
        "kredi|geri ödemeli borç kullanımını", "alım gücü|parayla alınabilen mal miktarını",
        "bütçe|gelir ve gider planını", "ithalat|yurt dışından mal almayı", "ihracat|yurt dışına mal satmayı",
        "cari denge|dış gelir ve gider dengesini", "merkez bankası|para politikasını yöneten kurumu",
        "para politikası|faiz ve para arzı kararlarını", "maliye politikası|vergi ve kamu harcaması kararlarını",
        "üretim|mal veya hizmet oluşturmayı", "tüketim|mal veya hizmet kullanmayı",
        "istihdam|çalışan kişi sayısını", "asgari ücret|en düşük yasal ücreti",
        "maaş|düzenli çalışma gelirini", "maliyet|üretim için katlanılan gideri",
        "kâr|gelirin maliyeti aşan kısmını", "zarar|maliyetin geliri aşmasını",
        "sermaye|üretim ve yatırım kaynağını", "stok|elde tutulan mal miktarını",
        "tedarik|ürün veya hizmet sağlamayı", "rekabet|piyasada yarışan firmaları",
        "tekel|piyasada tek satıcı gücünü", "hane halkı|aynı evde yaşayan ekonomik birimi",
        "kredi kartı|sonradan ödeme aracını", "borç|geri ödenmesi gereken yükümlülüğü",
        "varlık|ekonomik değeri olan unsuru", "portföy|yatırım araçları toplamını",
        "döviz rezervi|merkez bankasının yabancı para birikimini", "altın fiyatı|değerli maden piyasa değerini",
        "petrol fiyatı|enerji maliyetini etkileyen fiyatı", "kira|kullanım karşılığı ödenen bedeli",
        "kira artışı|kira bedelindeki yükselişi", "satın alma gücü|gelirin gerçek değerini",
        "para arzı|ekonomide dolaşan para miktarını", "talep şoku|satın alma isteğindeki ani değişimi",
        "arz şoku|üretim tarafındaki ani değişimi", "durgunluk|ekonomik hareketin zayıflamasını",
        "vergi indirimi|ödenecek verginin azalmasını", "kamu harcaması|devletin yaptığı gideri",
        "dış borç|yurt dışına olan borcu", "vade|ödeme süresini", "taksit|parçalı ödeme tutarını",
        "sigorta|risk için güvence sağlamayı", "emeklilik|çalışma sonrası gelir dönemini",
        "fon|toplu yatırım kaynağını", "hisse senedi|şirket ortaklık payını",
        "kripto varlık|dijital değer birimini", "nakit akışı|para giriş ve çıkışını",
        "brüt gelir|kesinti öncesi geliri", "net gelir|kesinti sonrası geliri", "piyasa değeri|varlığın güncel değerini"
    )
    bilim = @(
        "element|tek tür atomdan oluşan maddeyi", "proton|pozitif yüklü parçacığı",
        "nötron|yüksüz atom parçacığını", "elektron|negatif yüklü parçacığı", "iyon|elektrik yüklü atomu",
        "bileşik|farklı atomların birleşimini", "çözelti|maddenin homojen karışımını",
        "asit|pH değeri düşük maddeyi", "baz|pH değeri yüksek maddeyi", "pH|asitlik ve bazlık ölçüsünü",
        "ısı|enerji aktarımını", "sıcaklık|tanecik hareket düzeyini", "buharlaşma|sıvının gaza dönüşmesini",
        "yoğunlaşma|gazın sıvıya dönüşmesini", "erime|katının sıvıya dönüşmesini", "donma|sıvının katıya dönüşmesini",
        "kuvvet|hareketi değiştiren etkiyi", "hız|birim zamandaki yol almayı", "ivme|hız değişim oranını",
        "sürtünme|harekete karşı koyan kuvveti", "kaldıraç|kuvvetten kazanç sağlayan düzeneği",
        "elektrik akımı|yüklerin hareketini", "direnç|akımı zorlaştıran etkiyi", "voltaj|elektrik potansiyel farkını",
        "manyetik alan|mıknatıs etkisinin bulunduğu alanı", "ses|titreşimle yayılan dalgayı",
        "dalga|enerji taşıyan titreşimi", "frekans|bir saniyedeki titreşim sayısını", "ekosistem|canlı ve çevre ilişkisini",
        "besin zinciri|canlılar arası beslenme sırasını", "tür|benzer canlı grubunu",
        "gen|kalıtsal bilgi birimini", "kromozom|DNA taşıyan yapıyı", "mutasyon|genetik değişimi",
        "adaptasyon|çevreye uyum özelliğini", "antikor|savunma proteinini", "organ|vücuttaki görevli yapıyı",
        "kalp|kanı pompalayan organı", "akciğer|solunum organını", "sinir sistemi|vücut iletişim ağını",
        "hücresel solunum|enerji üretim sürecini", "mikroskop|küçük yapıları büyütmeyi",
        "teleskop|uzak gök cisimlerini gözlemlemeyi", "uydu|gezegen çevresinde dolanan cismi",
        "kuyruklu yıldız|buz ve toz içeren gökcismini", "galaksi|yıldız sistemleri topluluğunu",
        "atmosfer|gezegeni saran gaz tabakasını", "deprem|yer kabuğu sarsıntısını", "fay|yer kabuğu kırığını",
        "volkan|yer altı magmasının çıkışını", "mineral|doğal kristal maddeyi", "kayaç|mineral topluluğunu",
        "fosil|geçmiş canlı kalıntısını", "jeoloji|yer bilimini", "meteoroloji|hava olayları bilimini",
        "deney|kontrollü bilimsel sınamayı", "gözlem|olayı dikkatle incelemeyi", "hipotez|test edilebilir bilimsel tahmini"
    )
    teknoloji = @(
        "işletim sistemi|cihazın temel yazılımını", "uygulama|belirli iş yapan yazılımı",
        "işlemci|komutları çalıştıran birimi", "RAM|geçici çalışma belleğini", "depolama|verinin kalıcı tutulmasını",
        "anakart|donanımları bağlayan kartı", "ekran kartı|görüntü işlemeyi", "modem|internet bağlantısını sağlayan cihazı",
        "router|ağ trafiğini yönlendiren cihazı", "IP adresi|cihazın ağdaki adresini", "DNS|alan adını adrese çeviren sistemi",
        "güvenlik duvarı|ağ trafiğini süzen korumayı", "antivirüs|zararlı yazılım korumasını",
        "veri tabanı|düzenli veri saklama sistemini", "SQL|veri tabanı sorgu dilini", "açık kaynak|kodu görülebilen yazılımı",
        "kapalı kaynak|kodu kapalı yazılımı", "sürüm kontrol|kod değişikliklerini izlemeyi", "Git|sürüm kontrol aracını",
        "yazılım hatası|beklenmeyen program davranışını", "hata ayıklama|sorun bulma ve düzeltmeyi",
        "derleme|kodu çalışır hale getirmeyi", "derleyici|kodu makineye uygun biçime çeviren aracı",
        "mobil uygulama|telefon için yazılımı", "web sitesi|tarayıcıdan açılan sayfayı", "çerez|site oturum bilgisini",
        "oturum|kullanıcı giriş durumunu", "CAPTCHA|insan doğrulama testini", "biyometri|bedensel özellikle doğrulamayı",
        "parmak izi|biyometrik kimlik izini", "yüz tanıma|yüzle kimlik doğrulamayı", "NFC|yakın mesafe veri aktarımını",
        "e-imza|dijital imza doğrulamasını", "yapay sinir ağı|öğrenen hesaplama modelini",
        "sohbet robotu|metinle yanıt veren yazılımı", "görüntü işleme|görsel veriyi analiz etmeyi",
        "ses tanıma|konuşmayı metne çevirmeyi", "büyük veri|çok büyük veri kümelerini",
        "veri merkezi|sunucuların bulunduğu yapıyı", "CDN|içeriği yakın sunucudan dağıtmayı",
        "API anahtarı|servis erişim anahtarını", "token|geçici erişim bilgisini", "şifre yöneticisi|parolaları güvenli saklamayı",
        "VPN|bağlantıyı şifreli tünelle taşımayı", "proxy|aracı sunucu kullanımını", "spam|istenmeyen dijital iletiyi",
        "kimlik avı|sahte yolla bilgi çalmayı", "sızma testi|güvenlik açığı sınamasını", "erişilebilirlik|herkes için kullanılabilir tasarımı",
        "arayüz|kullanıcının gördüğü kullanım yüzünü", "kullanıcı deneyimi|ürünün kullanım hissini",
        "dokunmatik ekran|temasla kontrol edilen ekranı", "sensör|çevreden veri alan parçayı",
        "ivmeölçer|hareket değişimini ölçen sensörü", "kamera sensörü|ışığı dijital görüntüye çeviren parçayı",
        "pil sağlığı|bataryanın kapasite durumunu", "hızlı şarj|bataryayı kısa sürede doldurmayı"
    )
    sanat = @(
        "çizgi|görsel yön ve sınırı", "biçim|nesnenin dış yapısını", "doku|yüzey hissini",
        "ton|açık koyu değerini", "gölgelendirme|hacim hissi vermeyi", "anatomi|canlı form bilgisini",
        "eskiz|ön çizim çalışmasını", "tuval|resim yapılan yüzeyi", "fırça|boya sürme aracını",
        "palet|renk karıştırma yüzeyini", "seramik|kil temelli sanat üretimini", "gravür|kazıma baskı tekniğini",
        "kolaj|parçaları birleştirme tekniğini", "vitray|renkli cam sanatını", "sahne tasarımı|oyunun görsel ortamını",
        "kostüm|karakter kıyafet tasarımını", "dekor|sahne çevre düzenini", "senaryo|film veya oyun metnini",
        "kurgu|görüntüleri sıralama işlemini", "kamera açısı|çekim bakış yönünü", "yakın çekim|detayı büyüten planı",
        "montaj|çekimleri birleştirme işlemini", "bale|dans ve sahne disiplinini", "opera|müzikli sahne sanatını",
        "drama|ciddi anlatı türünü", "trajedi|acı sonlu dramatik türü", "komedi|güldürü amaçlı türü",
        "roman|uzun kurmaca anlatıyı", "öykü|kısa kurmaca anlatıyı", "şiir|ölçülü veya imgeli anlatımı",
        "imge|zihinde canlanan sanat görüntüsünü", "metafor|benzetmeye dayalı anlamı", "tema|eserin ana konusunu",
        "anlatıcı|hikayeyi aktaran sesi", "karakter|eserdeki kişiyi", "olay örgüsü|hikayedeki olay sırasını",
        "müzikal|şarkılı sahne eserini", "fotoğraf|ışıkla görüntü kaydetmeyi", "pozlama|ışık alma süresini",
        "diyafram|objektiften geçen ışık açıklığını", "enstantane|çekim süresini", "portre|kişi betimlemesini",
        "manzara resmi|doğa veya mekan betimini", "natürmort|cansız nesne resmini", "kaligrafi|güzel yazı sanatını",
        "grafiti|duvar yüzeyindeki görsel ifadeyi", "enstalasyon|mekana yayılan sanat düzenini",
        "performans sanatı|beden ve eylemle sanat üretimini", "çağdaş sanat|güncel sanat üretimini",
        "pop art|popüler kültür imgeleriyle sanatı", "realizm|gerçekçi anlatımı", "romantizm|duygu ve hayal vurgusunu",
        "sembolizm|simgeyle anlatımı", "fütürizm|hız ve modernlik vurgusunu", "dadaizm|alışılmış sanata karşı çıkışı",
        "art deco|geometrik süsleme üslubunu", "afiş|duyuru amaçlı görsel tasarımı"
    )
    muzik = @(
        "solfej|notaları sesle okumayı", "ölçü|müzikte zaman bölmesini", "usul|ritmik kalıp düzenini",
        "arpej|akor seslerini sırayla çalmayı", "gam|notaların sıralı dizisini", "tonalite|müziğin merkez ses düzenini",
        "majör|parlak duyulan dizi yapısını", "minör|daha hüzünlü duyulan dizi yapısını", "oktav|aynı sesin sekizli aralığını",
        "perde|ses yüksekliği basamağını", "tını|sesin karakter rengini", "dinamik|ses şiddeti değişimini",
        "forte|güçlü çalma işaretini", "piano|hafif çalma işaretini", "crescendo|sesin giderek yükselmesini",
        "decrescendo|sesin giderek azalmasını", "senkop|vurgunun beklenmeyen yere kaymasını", "metronom|tempo ölçme aracını",
        "akort|çalgıyı doğru sese ayarlamayı", "entonasyon|ses doğruluğunu", "vibrato|seste titreşim etkisini",
        "legato|sesleri bağlı çalmayı", "staccato|sesleri kısa ve kesik çalmayı", "konçerto|solist ve orkestra eserini",
        "sonat|çalgı için bestelenen formu", "senfoni|orkestra için geniş eseri", "aria|operada solo şarkıyı",
        "düet|iki kişiyle icrayı", "trio|üç kişiyle icrayı", "orkestral düzen|çalgıların birlikte planlanmasını",
        "bağlama|telli Türk halk çalgısını", "ney|üflemeli Türk müziği çalgısını", "kanun|telli Türk müziği çalgısını",
        "ud|perdesiz telli çalgıyı", "keman|yaylı çalgıyı", "gitar|telli çalgıyı", "davul|vurmalı çalgıyı",
        "piyano|tuşlu çalgıyı", "bas gitar|kalın frekanslı telli çalgıyı", "synthesizer|elektronik ses üreticisini",
        "kayıt|sesin saklanmasını", "miksaj|ses kanallarını dengelemeyi", "aranje|şarkının düzenlemesini",
        "beat|ritmik altyapıyı", "nakarat|şarkının tekrar eden bölümünü", "kıta|şarkı sözlerinin bölümünü",
        "köprü|şarkı bölümleri arasındaki geçişi", "intro|şarkının giriş bölümünü", "outro|şarkının bitiş bölümünü",
        "loop|tekrar eden ses döngüsünü", "sample|alınmış ses parçasını", "marş|coşkulu toplu müzik türünü",
        "ninni|uyutma amaçlı ezgiyi", "ilahi|dini içerikli müziği", "elektronik müzik|elektronik seslerle üretimi"
    )
    tarih = @(
        "İlk Çağ|eski uygarlıklar dönemini", "Orta Çağ|feodal ve dini düzen dönemini",
        "Yeni Çağ|keşifler ve dönüşümler dönemini", "Yakın Çağ|modern tarih dönemini",
        "Hititler|Anadolu'daki eski uygarlığı", "Sümerler|yazıyı kullanan Mezopotamya uygarlığını",
        "Lidyalılar|parayı kullanan Anadolu uygarlığını", "Urartular|Doğu Anadolu uygarlığını",
        "Frigler|Anadolu'da yaşamış eski topluluğu", "Mezopotamya|Fırat ve Dicle çevresi uygarlık alanını",
        "Anadolu Selçuklu|Anadolu'daki Türk devletini", "Büyük Selçuklu|Orta Asya ve İran merkezli Türk devletini",
        "Tanzimat|Osmanlı yenileşme dönemini", "Islahat Fermanı|hakları genişletme girişimini",
        "Meşrutiyet|anayasal monarşi düzenini", "Mondros Ateşkesi|Osmanlı için savaşı bitiren ateşkesi",
        "Sevr Antlaşması|Osmanlı'ya dayatılan ağır antlaşmayı", "Lozan Antlaşması|Türkiye'nin bağımsızlık belgesini",
        "Sakarya Meydan Muharebesi|Kurtuluş Savaşı'nın dönüm noktasını", "Büyük Taarruz|kesin zafer harekatını",
        "Mudanya Ateşkesi|savaş sonrası ateşkes sürecini", "Amasya Genelgesi|milli mücadelenin gerekçesini",
        "Erzurum Kongresi|bölgesel direniş kararlarını", "Sivas Kongresi|milli örgütlenmenin birleşmesini",
        "Misak-ı Milli|ulusal sınır hedefini", "saltanatın kaldırılması|monarşik yetkinin bitmesini",
        "hilafetin kaldırılması|dini-siyasi makamın sona ermesini", "medeni kanun|hukukta toplumsal düzenlemeyi",
        "kapitülasyonlar|yabancılara verilen ayrıcalıkları", "tımar sistemi|Osmanlı toprak ve asker düzenini",
        "devşirme sistemi|Osmanlı insan kaynağı düzenini", "lonca|esnaf örgütlenmesini", "vakıf|toplumsal hizmet kurumunu",
        "medrese|geleneksel eğitim kurumunu", "kervansaray|ticaret yolu konaklama yapısını",
        "feodalite|toprak temelli siyasi düzeni", "monarşi|tek kişinin yönetimini", "meclis|temsil ve karar organını",
        "koloni|başka devletin denetlediği bölgeyi", "sömürgecilik|kaynak ve bölge denetimini",
        "milliyetçilik|ulus temelli siyasi düşünceyi", "reform hareketleri|dini ve toplumsal yenilenmeyi",
        "Soğuk Savaş|iki bloklu siyasi gerilimi", "NATO|askeri savunma ittifakını",
        "Birleşmiş Milletler|uluslararası barış örgütünü", "Berlin Duvarı|soğuk savaş bölünmesini",
        "ateşkes|çatışmanın geçici durmasını", "göçebe yaşam|yer değiştiren toplum düzenini",
        "yerleşik yaşam|kalıcı yerleşim düzenini", "yazının icadı|tarihi çağların başlangıcını",
        "paranın icadı|ticarette ortak değişim aracını", "barış antlaşması|savaşı bitiren resmi uzlaşmayı"
    )
    guncel = @(
        "e-Devlet|dijital kamu hizmetini", "dijital kimlik|çevrim içi kimlik doğrulamayı",
        "çevrim içi alışveriş|internetten ürün almayı", "kargo takip|gönderi durumunu izlemeyi",
        "abonelik iptali|tekrarlı ödemeyi sonlandırmayı", "veri ihlali|kişisel bilginin açığa çıkmasını",
        "siber saldırı|dijital sisteme zarar verme girişimini", "sahte haber|gerçeğe aykırı haberi",
        "doğrulama sitesi|bilgi kontrolü yapan kaynağı", "afet çantası|acil durumda hazır malzemeyi",
        "iklim krizi|iklimde ciddi bozulmayı", "geri dönüşüm|atığı yeniden değerlendirmeyi",
        "elektrik tasarrufu|enerjiyi daha az kullanmayı", "su krizi|temiz suya erişim sorununu",
        "trafik yoğunluğu|yollardaki araç sıkışmasını", "toplu taşıma|ortak ulaşım sistemini",
        "akıllı şehir|teknoloji destekli kent yönetimini", "uzaktan eğitim|dijital ortamda öğrenmeyi",
        "hibrit çalışma|ofis ve uzaktan çalışmayı birleştirmeyi", "yapay zeka aracı|otomatik destek veren yazılımı",
        "algoritmik öneri|sistemin kişiye içerik önermesini", "ekran süresi|cihaz başında geçirilen zamanı",
        "dijital detoks|ekran kullanımına ara vermeyi", "bildirim yönetimi|uyarıları bilinçli ayarlamayı",
        "mahremiyet ayarı|kişisel görünürlüğü kontrol etmeyi", "çerez izni|site takip iznini",
        "konum izni|uygulamanın yer bilgisine erişmesini", "tüketici şikayeti|alıcı sorununun bildirilmesini",
        "iade hakkı|ürünü geri verme hakkını", "fatura kontrolü|ödeme bilgisini denetlemeyi",
        "bütçe planı|gelir gider düzenlemeyi", "kişisel finans|bireyin para yönetimini",
        "medya manipülasyonu|algıyı yönlendiren içerikleri", "kamu spotu|toplumsal bilgilendirme duyurusunu",
        "sosyal sorumluluk|toplum yararına davranışı", "gönüllülük|karşılıksız destek vermeyi",
        "bağış kampanyası|yardım için kaynak toplamayı", "acil uyarı|tehlike anındaki resmi bildirimi",
        "hava durumu uyarısı|meteorolojik risk bilgisini", "sağlık randevusu|muayene için zaman almayı",
        "aşı takvimi|aşı zaman planını", "çevre kirliliği|doğaya zarar veren atıkları",
        "plastik atık|doğada zor çözünen atığı", "karbon salımı|iklimi etkileyen gaz çıkışını",
        "gıda güvenliği|yiyeceğin sağlıklı olmasını", "etiket okuma|ürün bilgisini incelemeyi",
        "sürdürülebilir moda|kaynak dostu giyim yaklaşımını", "yerel seçim|belediye yönetimi seçimini",
        "kamu hizmeti|devletin sunduğu hizmeti", "enerji verimliliği|aynı işi daha az enerjiyle yapmayı",
        "yangın güvenliği|yangın riskini azaltmayı", "ilk yardım|acil durumda temel müdahaleyi",
        "psikolojik iyi oluş|ruhsal dengeyi korumayı", "stres yönetimi|baskıyla baş etmeyi",
        "zaman yönetimi|işleri planlı yürütmeyi", "dijital ödeme|telefon veya kartla ödeme yapmayı",
        "temassız ödeme|yaklaştırarak ödeme yapmayı", "mobil bankacılık|bankacılığı telefondan yapmayı"
    )
}

foreach ($key in $extraTopicsTr.Keys) {
    $topicsTr[$key] += Parse-TopicPairs $extraTopicsTr[$key] $key
}

$categoryMap = @(
    @{ key = "guncel"; name = "Güncel" },
    @{ key = "teknoloji"; name = "Teknoloji" },
    @{ key = "sanat"; name = "Sanat" },
    @{ key = "spor"; name = "Spor" },
    @{ key = "muzik"; name = "Müzik" },
    @{ key = "tarih"; name = "Tarih" }
)

$trBank = @()
$enBank = @()
foreach ($category in $categoryMap) {
    $trTemplates = Get-Templates "tr" $category.key
    $enTemplates = Get-Templates "en" $category.key
    $trFactItems = @()
    $enFactItems = @()
    if ($category.key -eq "tarih") {
        $yearTarget = [Math]::Min(500, $PerCategory)
        $trFactItems = New-YearFactBank "tr" $category.key $category.name $historyYearFactsTr $yearTarget
        $enFactItems = New-YearFactBank "en" $category.key $category.name $historyYearFactsEn $yearTarget
    }
    $trBank += $trFactItems
    $enBank += $enFactItems
    $trRemaining = $PerCategory - $trFactItems.Count
    $enRemaining = $PerCategory - $enFactItems.Count
    if ($trRemaining -gt 0) {
        $trBank += New-QuestionBank "tr" $category.key $category.name $topicsTr[$category.key] $trTemplates $factOpenersTr $wrongTrByCategory[$category.key] $trRemaining $simpleFactsTr[$category.key]
    }
    if ($enRemaining -gt 0) {
        $enBank += New-QuestionBank "en" $category.key $category.name $topicsEn[$category.key] $enTemplates $factOpenersEn $wrongEnByCategory[$category.key] $enRemaining $simpleFactsEn[$category.key]
    }
}

function Normalize-DifficultyCounts($bank, $categories, $perCategory, $lang) {
    if (($perCategory % 3) -ne 0) { return $bank }
    $target = [int]($perCategory / 3)
    $diffs = if ($lang -eq "tr") { @("kolay", "orta", "zor") } else { @("easy", "medium", "hard") }
    $easyName = if ($lang -eq "tr") { "kolay" } else { "easy" }
    foreach ($category in $categories) {
        $group = @($bank | Where-Object { $_.category -eq $category.name })
        $guard = 0
        while ($guard -lt 20) {
            $guard++
            $counts = @{}
            foreach ($diff in $diffs) {
                $counts[$diff] = @($group | Where-Object { $_.difficulty -eq $diff }).Count
            }
            $over = @($diffs | Where-Object { $counts[$_] -gt $target } | Select-Object -First 1)
            $under = @($diffs | Where-Object { $counts[$_] -lt $target } | Select-Object -First 1)
            if ($over.Count -eq 0 -or $under.Count -eq 0) { break }
            $moveCount = [Math]::Min($counts[$over[0]] - $target, $target - $counts[$under[0]])
            $candidates = @($group | Where-Object { $_.difficulty -eq $over[0] })
            if ($under[0] -eq $easyName) {
                $candidates = @($candidates | Where-Object { "$($_.question)".Length -le 92 -and "$($_.question)" -notmatch "(hangi kavram|hangi terim|hangi başlık|hangi ifad|aşağıdakilerden hangisidir|denince hangi)" })
            }
            $itemsToMove = @($candidates | Select-Object -Last $moveCount)
            if ($itemsToMove.Count -eq 0) { break }
            foreach ($item in $itemsToMove) {
                $item.difficulty = $under[0]
            }
        }
        if ($lang -eq "tr") {
            $longEasy = @($group | Where-Object { $_.difficulty -eq "kolay" -and "$($_.question)".Length -gt 92 })
            foreach ($easyItem in $longEasy) {
                $replacement = @($group | Where-Object { $_.difficulty -ne "kolay" -and "$($_.question)".Length -le 82 -and "$($_.question)" -notmatch "(hangi kavram|hangi terim|hangi başlık|hangi ifad|aşağıdakilerden hangisidir|denince hangi)" } | Select-Object -First 1)
                if ($replacement.Count -eq 0) { continue }
                $oldDiff = $replacement[0].difficulty
                $replacement[0].difficulty = "kolay"
                $easyItem.difficulty = $oldDiff
            }
        }
    }
    return $bank
}

$trBank = Normalize-DifficultyCounts $trBank $categoryMap $PerCategory "tr"
$enBank = Normalize-DifficultyCounts $enBank $categoryMap $PerCategory "en"

function Set-QuestionSources($bank) {
    foreach ($item in $bank) {
        $difficulty = "$($item.difficulty)"
        $source = if ($difficulty -eq "kolay" -or $difficulty -eq "easy") {
            "SadeBiL curated easy"
        } elseif ($difficulty -eq "orta" -or $difficulty -eq "medium") {
            "SadeBiL generated medium"
        } else {
            "SadeBiL generated hard"
        }
        if ($item.PSObject.Properties.Name -contains "source") {
            $item.source = $source
        } else {
            Add-Member -InputObject $item -NotePropertyName source -NotePropertyValue $source
        }
    }
    return $bank
}

$trBank = Set-QuestionSources $trBank
$enBank = Set-QuestionSources $enBank

if ([string]::IsNullOrWhiteSpace($AssetDir)) {
    if ([string]::IsNullOrWhiteSpace($env:SADEBIL_GENERATED_ASSETS)) {
        $assetDir = Join-Path $env:USERPROFILE "sadebil_generated_assets"
    } else {
        $assetDir = $env:SADEBIL_GENERATED_ASSETS
    }
} else {
    $assetDir = $AssetDir
}
New-Item -ItemType Directory -Force -Path $assetDir | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$trJson = $trBank | ConvertTo-Json -Depth 8
$enJson = $enBank | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText((Join-Path $assetDir "questions_tr.json"), $trJson, $utf8NoBom)
[System.IO.File]::WriteAllText((Join-Path $assetDir "questions_en.json"), $enJson, $utf8NoBom)

function Write-BankAsset($name, $items) {
    $json = @($items) | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText((Join-Path $assetDir $name), $json, $utf8NoBom)
}

function New-MixBank($bank, $perCategory, $categories) {
    $groups = @{}
    foreach ($category in $categories) {
        $groups[$category.name] = @($bank | Where-Object { $_.category -eq $category.name })
    }
    $mix = @()
    $target = $perCategory
    for ($i = 0; $i -lt $target; $i++) {
        $category = $categories[$i % $categories.Count]
        $group = $groups[$category.name]
        if ($group.Count -eq 0) { continue }
        $mix += $group[[int][Math]::Floor($i / $categories.Count) % $group.Count]
    }
    return $mix
}

$trMix = New-MixBank $trBank $PerCategory $categoryMap
$enMix = New-MixBank $enBank $PerCategory $categoryMap
Write-BankAsset "questions_tr_mix.json" $trMix
Write-BankAsset "questions_en_mix.json" $enMix
foreach ($category in $categoryMap) {
    Write-BankAsset ("questions_tr_{0}.json" -f $category.key) @($trBank | Where-Object { $_.category -eq $category.name })
    Write-BankAsset ("questions_en_{0}.json" -f $category.key) @($enBank | Where-Object { $_.category -eq $category.name })
}

Write-Output "questions_tr.json: $($trBank.Count) soru üretildi."
Write-Output "questions_en.json: $($enBank.Count) soru üretildi."
Write-Output "Kategori dosyaları: TR/EN mix + 6 kategori ayrı üretildi."
foreach ($category in $categoryMap) {
    Write-Output "$($category.name): TR $PerCategory / EN $PerCategory"
}
